// Import AVFoundation for generated offline score-preview audio.
import AVFoundation
// Import Foundation for timers, locks, and score timing.
import Foundation

// Describe one absolute-time group of audible generated lyre frequencies.
struct LyrePreviewEvent: Equatable {
    // Start this group after the preview begins.
    let timeMs: Int
    // Play these one-to-three note frequencies as a chord.
    let frequencies: [Double]
}

// Convert safe keyboard-score events into generated audible note groups.
enum LyrePreviewPlanner {
    // Preserve every score interval while accumulating absolute preview time.
    static func events(score: [ImportedScoreEvent]) -> [LyrePreviewEvent] {
        // Keep a running onset time across delay-before-event entries.
        var timeMs = 0
        // Prepare one output event per valid source chord.
        var planned: [LyrePreviewEvent] = []
        // Convert each authored event in playback order.
        for event in score {
            // Advance by the source-written delay before this onset.
            timeMs += max(0, event.delayMs)
            // Keep only known instrument keys inside this generated preview.
            let frequencies = event.keys.compactMap(frequency(for:))
            // Ignore an impossible empty chord without changing later timing.
            guard !frequencies.isEmpty else { continue }
            // Keep simultaneous source keys together in one audible chord.
            planned.append(LyrePreviewEvent(timeMs: timeMs, frequencies: frequencies))
        }
        // Return the exact score-derived preview schedule.
        return planned
    }

    // Map Genshin's three seven-note rows to C-major natural note frequencies.
    static func frequency(for key: String) -> Double? {
        // Keep one low-to-high key order matching the physical lyre rows.
        let keys = Array("zxcvbnmasdfghjqwertyu").map(String.init)
        // Require a valid known note key.
        guard let index = keys.firstIndex(of: key) else { return nil }
        // Use natural-note semitone offsets inside each seven-note octave.
        let naturalOffsets = [0, 2, 4, 5, 7, 9, 11]
        // Split the row index into octave and natural scale degree.
        let octave = index / 7
        let degree = index % 7
        // Make the low row C3 and rise by one octave for each keyboard row.
        let midi = 48 + octave * 12 + naturalOffsets[degree]
        // Convert the conventional MIDI pitch into Hertz for generated audio.
        return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}

// Play an approximate offline lyre preview without sending any keyboard events.
final class LyrePreviewPlayer {
    // Publish concise audio-preview state to the AppKit shell.
    var onStatus: ((String) -> Void)?
    // Let row controls become Stop only for the active preview card.
    var onPlaybackChange: ((String?) -> Void)?
    // Keep generated buffers and work items alive for their scheduled playback.
    private let engine = AVAudioEngine()
    // Use one player node because each buffer can contain a complete chord.
    private let playerNode = AVAudioPlayerNode()
    // Keep one standard stereo float format for all generated notes.
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    // Retain scheduled main-queue work so Stop can cancel it immediately.
    private var workItems: [DispatchWorkItem] = []
    // Distinguish a stopped/restarted preview from older scheduled completion blocks.
    private var generation = 0
    // Retain the active card identity for safe row redraws.
    private var activeID: String?

    // Configure the small audio graph once before any user action.
    init() {
        // Attach the source node to the private engine graph.
        engine.attach(playerNode)
        // Route generated preview audio through the normal macOS main mixer.
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    // Start one generated score preview at a normal or selected speed.
    func play(score: [ImportedScoreEvent], title: String, id: String, at speed: Double = 1.0) {
        // Convert only already-safe score events into an audio schedule.
        let events = LyrePreviewPlanner.events(score: score)
        // Explain an empty conversion instead of pretending to play sound.
        guard !events.isEmpty else { onStatus?("Nothing audible to preview in \(title). "); return }
        // Cancel a prior preview before replacing its schedule.
        stop(silent: true)
        // Reserve a fresh generation for every requested score.
        generation += 1
        let currentGeneration = generation
        // Remember the card whose Listen control should turn into Stop.
        activeID = id
        // Start the audio engine only after a person explicitly requests Listen.
        do {
            try engine.start()
            playerNode.play()
        } catch {
            onStatus?("Could not start the lyre preview: \(error.localizedDescription)")
            activeID = nil
            return
        }
        // Tell the UI that this score is now audible locally.
        onStatus?("Listening to \(title) locally.")
        onPlaybackChange?(id)
        // Convert score milliseconds through the requested speed safely.
        let safeSpeed = max(0.1, speed)
        // Schedule each chord on the main queue at its authored onset.
        for event in events {
            let delay = Double(event.timeMs) / 1_000.0 / safeSpeed
            let item = DispatchWorkItem { [weak self] in
                // Prevent an older stopped schedule from adding late sound.
                guard let self, self.generation == currentGeneration else { return }
                // Create and schedule one short generated natural-note chord.
                self.playerNode.scheduleBuffer(self.buffer(for: event.frequencies), completionHandler: nil)
            }
            // Retain cancellation access before dispatching this exact item.
            workItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        // Stop the audio graph just after the final chord's short decay.
        let ending = Double(events.last!.timeMs) / 1_000.0 / safeSpeed + 0.55
        let completion = DispatchWorkItem { [weak self] in
            // Finish only the same active preview generation.
            guard let self, self.generation == currentGeneration else { return }
            self.stop(silent: false)
        }
        // Keep completion cancellable like every note event.
        workItems.append(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + ending, execute: completion)
    }

    // Stop generated audio and invalidate every pending scheduled note.
    func stop(silent: Bool = false) {
        // Advance the generation before cancelling so racing work becomes a no-op.
        generation += 1
        // Cancel all pending source-time dispatch work.
        workItems.forEach { $0.cancel() }
        // Drop cancelled work immediately to avoid retaining score closures.
        workItems.removeAll()
        // Stop current buffers and reset the node timeline.
        playerNode.stop()
        // Stop the engine when no generated preview is active.
        engine.stop()
        // Remember whether the UI actually had a row to redraw.
        let hadActivePreview = activeID != nil
        // Clear the active identity after the audio graph is silent.
        activeID = nil
        // Redraw only when a visible control had changed to Stop.
        if hadActivePreview { onPlaybackChange?(nil) }
        // Keep normal completion quiet while explicit card Stop gives feedback.
        if !silent && hadActivePreview { onStatus?("Preview stopped.") }
    }

    // Render one brief decaying chord buffer from generated sine waves.
    private func buffer(for frequencies: [Double]) -> AVAudioPCMBuffer {
        // Use a fixed short decay so dense scores remain light and understandable.
        let frameCount: AVAudioFrameCount = 16_000
        // Allocate one non-interleaved stereo float buffer in the graph format.
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        // Mark every allocated frame as valid audible output.
        buffer.frameLength = frameCount
        // Read the writable left/right float channels.
        let channels = buffer.floatChannelData!
        // Mix every requested chord note into each output frame.
        for frame in 0..<Int(frameCount) {
            // Calculate source time once for this stereo frame.
            let time = Double(frame) / format.sampleRate
            // Apply a quick exponential envelope and keep chord volume bounded.
            let envelope = exp(-time * 7.0) * 0.22 / Double(max(1, frequencies.count))
            // Sum every simultaneous frequency into one natural lyre-like chord.
            let sample = frequencies.reduce(0.0) { $0 + sin(2.0 * .pi * $1 * time) } * envelope
            // Copy the same mono generated note into left and right channels.
            channels[0][frame] = Float(sample)
            channels[1][frame] = Float(sample)
        }
        // Return the fully rendered small chord buffer to the player node.
        return buffer
    }
}
