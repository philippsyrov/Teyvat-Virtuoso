// Keep import defaults and playback timing testable without opening AppKit or sending keys.
import Foundation

// Describe the non-destructive settings applied to every newly opened MIDI.
struct ImportDefaults {
    let transpose: Int
    let missingNotePolicy: MissingNotePolicy
    let mergeToleranceMs: Int
    let playbackSpeed: Double

    // Preserve source pitches/onsets and never guess unavailable black-key notes.
    static let raw = ImportDefaults(transpose: 0, missingNotePolicy: .skip, mergeToleranceMs: 0, playbackSpeed: 1.0)

    // Apply the raw mapping to the musical tracks exposed by this MIDI.
    func options(enabledTrackIndexes: Set<Int>) -> MidiImportOptions {
        MidiImportOptions(
            enabledTrackIndexes: enabledTrackIndexes,
            transpose: transpose,
            missingNotePolicy: missingNotePolicy,
            mergeToleranceMs: mergeToleranceMs
        )
    }
}

// Derive the imported keyboard-preview button from the common active playback identity.
struct ImportedPreviewControl {
    let activePlaybackID: String?

    var shouldStop: Bool { activePlaybackID == "import:preview" }
    var title: String { shouldStop ? "Stop" : "Preview — 5 second focus time" }
}

// Keep saved-song slider values readable and inside the range the player supports.
struct SavedSpeedControl {
    let playbackSpeed: Double

    init(playbackSpeed: Double) {
        let clamped = min(2.00, max(0.90, playbackSpeed))
        self.playbackSpeed = (clamped * 20).rounded() / 20
    }

    var percentageLabel: String {
        "\(Int((playbackSpeed * 100).rounded()))%"
    }
}

// Convert relative score delays into source-faithful absolute playback targets.
enum PlaybackTimeline {
    static func targetSeconds(for score: [ImportedScoreEvent], speed: Double) -> [Double] {
        let safeSpeed = max(0.1, speed)
        var elapsedMilliseconds = 0
        return score.map { event in
            elapsedMilliseconds += max(0, event.delayMs)
            return Double(elapsedMilliseconds) / 1_000 / safeSpeed
        }
    }

    // Drive the real performer from absolute targets so chord holds cannot accumulate drift.
    static func perform(
        score: [ImportedScoreEvent],
        speed: Double,
        waitUntil: (Double) -> Bool,
        playChord: ([String]) -> Void
    ) -> Bool {
        for (event, target) in zip(score, targetSeconds(for: score, speed: speed)) {
            guard waitUntil(target) else { return false }
            playChord(event.keys)
        }
        return true
    }
}
