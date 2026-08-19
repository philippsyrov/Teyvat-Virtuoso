// Import Foundation for MIDI byte buffers and editable file data.
import Foundation

// Describe the one export failure that can occur before any file is written.
enum EditableMidiExportError: LocalizedError {
    // Reject a score without musical events instead of writing a misleading empty file.
    case emptyScore

    // Convert the bounded export failure into a readable status message.
    var errorDescription: String? {
        // Explain why no `.mid` file was created.
        return "There are no mapped lyre notes to export."
    }
}

// Write cached mapped lyre events as a standard editable MIDI file.
struct EditableMidiExporter {
    // Use a conventional PPQN that every MIDI editor can read without special timing support.
    private static let ticksPerQuarter = 480
    // Keep the generated MIDI tempo fixed at 120 BPM so one score millisecond maps to 0.96 ticks.
    private static let microsecondsPerQuarter = 500_000
    // Map the three Genshin lyre keyboard rows to adjacent natural MIDI-note octaves.
    private static let midiNotes: [String: UInt8] = [
        "z": 48, "x": 50, "c": 52, "v": 53, "b": 55, "n": 57, "m": 59,
        "a": 60, "s": 62, "d": 64, "f": 65, "g": 67, "h": 69, "j": 71,
        "q": 72, "w": 74, "e": 76, "r": 77, "t": 79, "y": 81, "u": 83,
    ]

    // Represent one timestamped MIDI event before compact delta encoding.
    private struct ScheduledEvent {
        // Store absolute 120-BPM ticks until the final sorted track is written.
        let tick: Int
        // Put note-offs first when events share a tick so repeated keys never stick.
        let ordering: Int
        // Store the complete channel-event bytes excluding the delta-time prefix.
        let bytes: [UInt8]
    }

    // Convert safe mapped score events into one format-0 Standard MIDI file.
    static func makeFile(score: [ImportedScoreEvent]) throws -> Data {
        // Reject an absent arrangement before emitting only tempo metadata.
        guard !score.isEmpty else { throw EditableMidiExportError.emptyScore }
        // Convert each relative score delay into one absolute editable MIDI onset.
        var onsets: [(tick: Int, keys: [String])] = []
        // Begin the relative time cursor at the first MIDI tick.
        var tick = 0
        // Preserve the exact event order supplied by the validated local score.
        for event in score {
            // Translate milliseconds to 120-BPM ticks while preserving sub-quarter-note timing.
            tick += Int((Double(event.delayMs) * 0.96).rounded())
            // Keep only known lyre keys before writing any channel messages.
            let keys = event.keys.filter { midiNotes[$0] != nil }
            // Ignore a malformed empty group rather than producing an invalid MIDI event.
            if !keys.isEmpty { onsets.append((tick, keys)) }
        }
        // Reject a score whose events contained no recognised lyre keys.
        guard !onsets.isEmpty else { throw EditableMidiExportError.emptyScore }
        // Accumulate note-ons and note-offs in absolute time before delta encoding them.
        var scheduled: [ScheduledEvent] = []
        // Emit every authored chord with a short editable duration suited to the next onset.
        for index in onsets.indices {
            // Capture this chord's preserved absolute onset.
            let onset = onsets[index]
            // Limit note length before the next onset so fast repeated keys remain editable and audible.
            let nextTick = index + 1 < onsets.count ? onsets[index + 1].tick : onset.tick + 360
            // Keep a minimum 25-ms note while avoiding a long held chord across the following event.
            let duration = max(24, min(360, max(24, nextTick - onset.tick - 1)))
            // Write every key in the group as a simultaneous channel-1 note-on and note-off pair.
            for key in onset.keys {
                // Resolve the already validated physical lyre key to its natural MIDI pitch.
                guard let note = midiNotes[key] else { continue }
                // Use velocity 96 for a normal, easy-to-edit piano-roll note.
                scheduled.append(ScheduledEvent(tick: onset.tick, ordering: 1, bytes: [0x90, note, 96]))
                // End the note before a same-tick repeated note-on can occur.
                scheduled.append(ScheduledEvent(tick: onset.tick + duration, ordering: 0, bytes: [0x80, note, 0]))
            }
        }
        // Sort by absolute time and release notes before starting a repeated note at that time.
        scheduled.sort { left, right in
            left.tick == right.tick ? left.ordering < right.ordering : left.tick < right.tick
        }
        // Start the single editable track with tempo and clear provenance metadata.
        var track: [UInt8] = [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        // Identify the generated track inside MIDI editors without claiming it is the source arrangement.
        let name = Array("Teyvat Virtuoso lyre export".utf8)
        track += [0x00, 0xFF, 0x03, UInt8(name.count)] + name
        // Delta-encode every sorted channel event into the Standard MIDI track.
        var previousTick = 0
        for event in scheduled {
            // Write only the elapsed ticks since the previously emitted event.
            track += variableLength(event.tick - previousTick)
            // Append the full note-on or note-off channel message.
            track += event.bytes
            // Advance the delta-time cursor after this exact event.
            previousTick = event.tick
        }
        // Terminate the track explicitly at its final musical position.
        track += [0x00, 0xFF, 0x2F, 0x00]
        // Assemble the fixed format-0 header plus the declared track byte count.
        var file = Array("MThd".utf8) + [0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x01, 0x01, 0xE0]
        // Append the complete `MTrk` chunk header and exact encoded track payload.
        file += Array("MTrk".utf8) + bigEndian(track.count) + track
        // Return ordinary Data ready for a Downloads write.
        return Data(file)
    }

    // Encode one non-negative MIDI delta-time value using Standard MIDI variable-length bytes.
    private static func variableLength(_ value: Int) -> [UInt8] {
        // Start with one guaranteed payload byte.
        var bytes = [UInt8(value & 0x7F)]
        // Shift remaining seven-bit groups until the value is fully represented.
        var remaining = value >> 7
        // Prefix each earlier group with the continuation bit.
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        // Return the compact safe delta-time sequence.
        return bytes
    }

    // Encode one chunk length as exactly four big-endian bytes.
    private static func bigEndian(_ value: Int) -> [UInt8] {
        // Convert the bounded track length to Standard MIDI's unsigned 32-bit representation.
        return [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
