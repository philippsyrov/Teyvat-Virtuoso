// Import Foundation for Data and process termination in this standalone test executable.
import Foundation

// Fail immediately with a readable message when an engine contract is broken.
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Evaluate the condition only once so assertions remain deterministic.
    guard condition() else {
        // Print the exact failed behavior for the Python test harness.
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        // Use a nonzero exit code so the surrounding unit test detects the failure.
        exit(1)
    }
}

// Encode one unsigned integer using MIDI's variable-length quantity format.
func variableLength(_ value: Int) -> [UInt8] {
    // Start with the low seven payload bits.
    var bytes = [UInt8(value & 0x7F)]
    // Shift through remaining seven-bit groups from low to high.
    var remaining = value >> 7
    while remaining > 0 {
        // Mark every preceding group as continued.
        bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
        // Move to the next group.
        remaining >>= 7
    }
    // Return a valid one-to-four-byte MIDI quantity.
    return bytes
}

// Wrap raw event bytes in one Standard MIDI track chunk.
func trackChunk(_ events: [UInt8]) -> [UInt8] {
    // Store the event payload length as a big-endian 32-bit value.
    let length = UInt32(events.count)
    // Prefix the payload with the standard MTrk identifier and length.
    return Array("MTrk".utf8) + [
        UInt8((length >> 24) & 0xFF),
        UInt8((length >> 16) & 0xFF),
        UInt8((length >> 8) & 0xFF),
        UInt8(length & 0xFF),
    ] + events
}

// Build a compact format-one MIDI fixture with conductor and named piano tracks.
func fixtureMidi() -> Data {
    // Set 120 BPM at tick zero, then end the conductor track.
    let conductor: [UInt8] = [
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,
        0x00, 0xFF, 0x2F, 0x00,
    ]
    // Name the piano track, start C and E together using running status, then release at one beat.
    let piano: [UInt8] = [
        0x00, 0xFF, 0x03, 0x05, 0x50, 0x69, 0x61, 0x6E, 0x6F,
        0x00, 0x90, 0x3C, 0x64,
        0x00, 0x40, 0x64,
    ] + variableLength(480) + [
        0x80, 0x3C, 0x00,
        0x00, 0x40, 0x00,
        0x00, 0xFF, 0x2F, 0x00,
    ]
    // Declare format one, two tracks, and 480 ticks per quarter note.
    let header: [UInt8] = Array("MThd".utf8) + [
        0x00, 0x00, 0x00, 0x06,
        0x00, 0x01,
        0x00, 0x02,
        0x01, 0xE0,
    ]
    // Concatenate the complete Standard MIDI file.
    return Data(header + trackChunk(conductor) + trackChunk(piano))
}

// Run the engine contract tests without a separate test framework dependency.
@main
struct MidiEngineTests {
    // Parse the fixture and validate its musical meaning.
    static func main() throws {
        // Smoke-parse any real MIDI paths supplied after the executable name.
        for path in CommandLine.arguments.dropFirst() {
            // Read the private source in place without copying or modifying it.
            let realDocument = try MidiDocument.parse(data: Data(contentsOf: URL(fileURLWithPath: path)))
            // Print compact evidence for manual build verification.
            print("SMOKE \(URL(fileURLWithPath: path).lastPathComponent): \(realDocument.tracks.count) tracks, \(Int(realDocument.durationMs.rounded())) ms, best \(realDocument.bestTranspose)")
        }
        // Parse the in-memory source through the production engine.
        let document = try MidiDocument.parse(data: fixtureMidi())
        // Hide the conductor chunk and expose only the musical piano track.
        expect(document.tracks.count == 1, "expected one musical track")
        // Preserve the original track index for UI selection.
        expect(document.tracks[0].index == 1, "expected original MIDI track index")
        // Preserve the authored track name for the checkbox label.
        expect(document.tracks[0].name == "Piano", "expected named piano track")
        // Decode the running-status E note as a second note onset.
        expect(document.tracks[0].noteCount == 2, "expected two parsed note onsets")
        // Recognise the equal-tick C and E as one true chord onset.
        expect(document.tracks[0].chordOnsets == 1, "expected one chord onset")
        // Convert one 120-BPM quarter note into 500 milliseconds.
        expect(abs(document.durationMs - 500) < 0.1, "expected source tempo conversion")
        // Leave an already-natural C-major fixture untransposed.
        expect(document.bestTranspose == 0, "expected zero best transpose")
        // Build a direct reduction fixture containing two tracks and an overfull near-chord.
        let reductionDocument = MidiDocument(
            tracks: [
                MidiTrackInfo(index: 1, name: "Lead", noteCount: 4, minimumNote: 48, maximumNote: 59, chordOnsets: 2),
                MidiTrackInfo(index: 2, name: "Other", noteCount: 1, minimumNote: 60, maximumNote: 60, chordOnsets: 0),
            ],
            durationMs: 500,
            bestTranspose: 0,
            ticksPerQuarter: 480,
            notes: [
                MidiNoteOn(trackIndex: 1, tick: 0, note: 48),
                MidiNoteOn(trackIndex: 1, tick: 0, note: 52),
                MidiNoteOn(trackIndex: 1, tick: 10, note: 55),
                MidiNoteOn(trackIndex: 1, tick: 10, note: 59),
                MidiNoteOn(trackIndex: 2, tick: 480, note: 60),
            ],
            tempos: [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
        )
        // Convert only the selected lead track and merge nearby source onsets.
        let merged = reductionDocument.makeScore(options: MidiImportOptions(
            enabledTrackIndexes: [1],
            transpose: 0,
            missingNotePolicy: .skip,
            mergeToleranceMs: 15
        ))
        // Merge the four nearby pitches into one safe event.
        expect(merged.count == 1, "expected nearby onset merging")
        // Cap the emitted chord at three distinct Genshin keys.
        expect(merged[0].keys == ["z", "c", "b"], "expected stable three-key chord cap")
        // Exclude notes belonging to unchecked tracks.
        expect(!merged[0].keys.contains("a"), "expected track selection")

        // Build one chromatic source note for explicit missing-note policy checks.
        let chromaticDocument = MidiDocument(
            tracks: [MidiTrackInfo(index: 0, name: "Chromatic", noteCount: 1, minimumNote: 61, maximumNote: 61, chordOnsets: 0)],
            durationMs: 0,
            bestTranspose: 0,
            ticksPerQuarter: 480,
            notes: [MidiNoteOn(trackIndex: 0, tick: 0, note: 61)],
            tempos: [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
        )
        // Skip a chromatic note when strict mapping is selected.
        expect(chromaticDocument.makeScore(options: MidiImportOptions(enabledTrackIndexes: [0], transpose: 0, missingNotePolicy: .skip, mergeToleranceMs: 0)).isEmpty, "expected strict chromatic skip")
        // Snap C-sharp down to middle-row C when requested.
        expect(chromaticDocument.makeScore(options: MidiImportOptions(enabledTrackIndexes: [0], transpose: 0, missingNotePolicy: .down, mergeToleranceMs: 0)).first?.keys == ["a"], "expected downward chromatic snap")
        // Snap C-sharp up to middle-row D when requested.
        expect(chromaticDocument.makeScore(options: MidiImportOptions(enabledTrackIndexes: [0], transpose: 0, missingNotePolicy: .up, mergeToleranceMs: 0)).first?.keys == ["s"], "expected upward chromatic snap")
        // Apply one shared transpose before pitch-class mapping.
        expect(chromaticDocument.makeScore(options: MidiImportOptions(enabledTrackIndexes: [0], transpose: 1, missingNotePolicy: .skip, mergeToleranceMs: 0)).first?.keys == ["s"], "expected shared transpose")

        // Fold pitches by octaves into the playable three-row window.
        let foldedDocument = MidiDocument(
            tracks: [MidiTrackInfo(index: 0, name: "Wide", noteCount: 2, minimumNote: 36, maximumNote: 96, chordOnsets: 1)],
            durationMs: 0,
            bestTranspose: 0,
            ticksPerQuarter: 480,
            notes: [MidiNoteOn(trackIndex: 0, tick: 0, note: 36), MidiNoteOn(trackIndex: 0, tick: 0, note: 96)],
            tempos: [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
        )
        // Preserve pitch class while fitting low and high extremes onto visible rows.
        expect(foldedDocument.makeScore(options: MidiImportOptions(enabledTrackIndexes: [0], transpose: 0, missingNotePolicy: .skip, mergeToleranceMs: 0)).first?.keys == ["z", "q"], "expected octave folding")
        // Confirm success for the surrounding Python harness.
        print("MidiEngineTests passed")
    }
}
