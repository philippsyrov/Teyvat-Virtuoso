// Import Foundation for byte buffers, text decoding, and user-facing parser errors.
import Foundation

// Describe malformed or unsupported Standard MIDI input without crashing the app.
enum MidiParseError: LocalizedError {
    // The source ended before a declared value or chunk was complete.
    case truncated(String)
    // The source did not contain the required Standard MIDI header.
    case invalidHeader
    // The source used time-code timing, which this musical-tempo engine does not support.
    case unsupportedSMPTE
    // The source contained an event that could not be decoded safely.
    case malformedEvent(String)

    // Convert parser failures into concise messages suitable for the app status label.
    var errorDescription: String? {
        // Match each bounded failure to one direct explanation.
        switch self {
        case .truncated(let context): return "The MIDI ended while reading \(context)."
        case .invalidHeader: return "This file does not have a valid Standard MIDI header."
        case .unsupportedSMPTE: return "SMPTE-timed MIDI files are not supported yet."
        case .malformedEvent(let context): return "The MIDI contains a malformed \(context)."
        }
    }
}

// Expose one musical track to the native checkbox list.
struct MidiTrackInfo: Equatable {
    // Preserve the source track index used by import options.
    let index: Int
    // Preserve an authored track name or provide a stable fallback.
    let name: String
    // Count audible, non-drum note onsets.
    let noteCount: Int
    // Record the lowest source MIDI pitch.
    let minimumNote: Int
    // Record the highest source MIDI pitch.
    let maximumNote: Int
    // Count timestamps containing more than one note onset.
    let chordOnsets: Int
}

// Keep one source note onset in musical tick time until tempo conversion is requested.
struct MidiNoteOn {
    // Identify the source track for UI filtering.
    let trackIndex: Int
    // Preserve the exact absolute source tick.
    let tick: Int
    // Preserve the MIDI pitch number.
    let note: Int
}

// Keep one global tempo instruction from a conductor or musical track.
struct MidiTempoChange {
    // Record when this tempo becomes active.
    let tick: Int
    // Record microseconds per quarter note exactly as authored.
    let microsecondsPerQuarter: Int
}

// Make the handling of unavailable black-key notes an explicit user choice.
enum MissingNotePolicy: String, CaseIterable {
    // Drop chromatic notes and preserve only directly playable source pitches.
    case skip
    // Move a chromatic note downward to the closest natural pitch.
    case down
    // Move a chromatic note upward to the closest natural pitch.
    case up
}

// Collect the user's deterministic MIDI reduction choices.
struct MidiImportOptions {
    // Include only source tracks whose checkboxes are enabled.
    let enabledTrackIndexes: Set<Int>
    // Apply one shared semitone shift before mapping any selected track.
    let transpose: Int
    // Decide how the lyre should handle unavailable chromatic pitches.
    let missingNotePolicy: MissingNotePolicy
    // Merge source onsets within this many milliseconds into one chord.
    let mergeToleranceMs: Int
}

// Use the same compact JSON event contract as the existing prepared-score player.
struct ImportedScoreEvent: Codable, Equatable {
    // Wait this many milliseconds after the preceding emitted group.
    let delayMs: Int
    // Press these one-to-three mapped Genshin keys together.
    let keys: [String]
}

// Read bounded big-endian and variable-length MIDI values from one byte array.
private struct MidiByteReader {
    // Own the bytes belonging to the current file or track chunk.
    let bytes: [UInt8]
    // Point to the next unread byte.
    var offset = 0

    // Report how many bytes remain inside this bounded reader.
    var remaining: Int { bytes.count - offset }

    // Read one byte or fail at this precise parser boundary.
    mutating func readByte(_ context: String) throws -> UInt8 {
        // Reject reads beyond the declared source or chunk length.
        guard offset < bytes.count else { throw MidiParseError.truncated(context) }
        // Return the current byte and advance once.
        defer { offset += 1 }
        return bytes[offset]
    }

    // Read a fixed number of bytes without escaping this reader's boundary.
    mutating func readBytes(_ count: Int, _ context: String) throws -> [UInt8] {
        // Reject negative or incomplete ranges before slicing the array.
        guard count >= 0, offset + count <= bytes.count else { throw MidiParseError.truncated(context) }
        // Copy the requested bounded range.
        let value = Array(bytes[offset..<(offset + count)])
        // Advance past the copied range.
        offset += count
        // Return the independent byte array.
        return value
    }

    // Read one MIDI big-endian unsigned 16-bit integer.
    mutating func readUInt16(_ context: String) throws -> Int {
        // Read the high byte first as required by Standard MIDI files.
        let high = Int(try readByte(context))
        // Read the low byte second.
        let low = Int(try readByte(context))
        // Combine both bytes into a host-sized integer.
        return (high << 8) | low
    }

    // Read one MIDI big-endian unsigned 32-bit integer.
    mutating func readUInt32(_ context: String) throws -> Int {
        // Build the result one high-to-low byte at a time.
        var value = 0
        for _ in 0..<4 {
            value = (value << 8) | Int(try readByte(context))
        }
        // Return the complete declared chunk length.
        return value
    }

    // Read one Standard MIDI variable-length quantity with its four-byte safety cap.
    mutating func readVariableLength(_ context: String) throws -> Int {
        // Accumulate seven payload bits per byte.
        var value = 0
        // Standard MIDI permits at most four bytes for this quantity.
        for _ in 0..<4 {
            // Read the next continuation/payload byte.
            let byte = try readByte(context)
            // Append its low seven payload bits.
            value = (value << 7) | Int(byte & 0x7F)
            // Stop when the continuation flag is clear.
            if byte & 0x80 == 0 { return value }
        }
        // Reject an unterminated fifth-byte quantity.
        throw MidiParseError.malformedEvent(context)
    }
}

// Represent a parsed Standard MIDI file and its import-facing analysis.
struct MidiDocument {
    // Expose only tracks that contain audible pitched notes.
    let tracks: [MidiTrackInfo]
    // Expose the source duration after applying its global tempo map.
    let durationMs: Double
    // Recommend one shared key change with the highest natural-note fit.
    let bestTranspose: Int
    // Preserve the source timing resolution for score generation.
    let ticksPerQuarter: Int
    // Preserve all audible source note onsets for later selected-track reduction.
    let notes: [MidiNoteOn]
    // Preserve all source tempo changes for exact onset conversion.
    let tempos: [MidiTempoChange]

    // Parse a complete in-memory Standard MIDI file.
    static func parse(data: Data) throws -> MidiDocument {
        // Copy the immutable source into the small bounded byte reader.
        var reader = MidiByteReader(bytes: Array(data))
        // Require the canonical MIDI header marker.
        guard try reader.readBytes(4, "header") == Array("MThd".utf8) else {
            throw MidiParseError.invalidHeader
        }
        // Read and validate the declared header payload length.
        let headerLength = try reader.readUInt32("header length")
        guard headerLength >= 6 else { throw MidiParseError.invalidHeader }
        // Accept format zero, one, or two structurally; track timing remains independently parsed.
        _ = try reader.readUInt16("format")
        // Read the exact number of following chunks declared by the header.
        let trackCount = try reader.readUInt16("track count")
        // Read the pulses-per-quarter timing division.
        let division = try reader.readUInt16("timing division")
        // Reject negative/SMPTE divisions before tempo arithmetic.
        guard division & 0x8000 == 0, division > 0 else { throw MidiParseError.unsupportedSMPTE }
        // Skip any vendor extension bytes in a longer header.
        if headerLength > 6 { _ = try reader.readBytes(headerLength - 6, "extended header") }

        // Collect audible notes across all musical tracks.
        var notes: [MidiNoteOn] = []
        // Collect global tempo changes from any track.
        var tempos: [MidiTempoChange] = [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
        // Preserve per-track analysis for the UI.
        var trackInfos: [MidiTrackInfo] = []
        // Track the last event tick, including note releases and end markers.
        var maximumTick = 0

        // Parse each declared chunk in source order.
        for trackIndex in 0..<trackCount {
            // Require the canonical track marker.
            guard try reader.readBytes(4, "track marker") == Array("MTrk".utf8) else {
                throw MidiParseError.malformedEvent("track marker")
            }
            // Bound this track to its declared payload length.
            let trackLength = try reader.readUInt32("track length")
            var trackReader = MidiByteReader(bytes: try reader.readBytes(trackLength, "track data"))
            // Rebuild absolute tick positions from event delta times.
            var absoluteTick = 0
            // Preserve channel running status between eligible events.
            var runningStatus: UInt8?
            // Save an authored name if present.
            var trackName = "Track \(trackIndex + 1)"
            // Collect this track's pitches and onset counts for analysis.
            var trackNotes: [Int] = []
            var onsetCounts: [Int: Int] = [:]

            // Decode events until this bounded chunk is exhausted.
            while trackReader.remaining > 0 {
                // Advance by the event's delta tick quantity.
                absoluteTick += try trackReader.readVariableLength("event delta time")
                // Keep the full file duration even when the final event is a note release.
                maximumTick = max(maximumTick, absoluteTick)
                // Read either a new status byte or the first data byte under running status.
                let statusOrData = try trackReader.readByte("event status")
                // Separate the resolved status from an optional already-read first data byte.
                let status: UInt8
                let firstData: UInt8?
                if statusOrData & 0x80 != 0 {
                    status = statusOrData
                    firstData = nil
                } else {
                    guard let previous = runningStatus else {
                        throw MidiParseError.malformedEvent("running status")
                    }
                    status = previous
                    firstData = statusOrData
                }

                // Decode meta events with their own type and variable payload length.
                if status == 0xFF {
                    // Read the meta event type.
                    let type = try trackReader.readByte("meta event type")
                    // Bound the following meta payload.
                    let length = try trackReader.readVariableLength("meta event length")
                    let payload = try trackReader.readBytes(length, "meta event payload")
                    // Preserve a readable sequence/track name.
                    if type == 0x03, let decoded = String(bytes: payload, encoding: .utf8), !decoded.isEmpty {
                        trackName = decoded
                    }
                    // Preserve exact three-byte tempo instructions.
                    if type == 0x51, payload.count == 3 {
                        let tempo = (Int(payload[0]) << 16) | (Int(payload[1]) << 8) | Int(payload[2])
                        tempos.append(MidiTempoChange(tick: absoluteTick, microsecondsPerQuarter: tempo))
                    }
                    // Meta events do not replace the current channel running status.
                    continue
                }

                // Skip bounded system-exclusive payloads and clear channel running status.
                if status == 0xF0 || status == 0xF7 {
                    let length = try trackReader.readVariableLength("system-exclusive length")
                    _ = try trackReader.readBytes(length, "system-exclusive payload")
                    runningStatus = nil
                    continue
                }

                // Require an ordinary channel status for all remaining events.
                guard status >= 0x80 && status <= 0xEF else {
                    throw MidiParseError.malformedEvent("channel event")
                }
                // Channel messages become the new reusable running status.
                runningStatus = status
                // Program-change and channel-pressure messages have one data byte; all others have two.
                let kind = status & 0xF0
                let dataCount = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
                // Use the already-read running-status data byte when present.
                var dataBytes: [UInt8] = []
                if let firstData { dataBytes.append(firstData) }
                // Read the remaining required channel data bytes.
                while dataBytes.count < dataCount {
                    dataBytes.append(try trackReader.readByte("channel event data"))
                }
                // Keep audible note-on messages and deliberately ignore MIDI drum channel ten.
                if kind == 0x90, dataBytes.count == 2, dataBytes[1] > 0, status & 0x0F != 9 {
                    let pitch = Int(dataBytes[0])
                    notes.append(MidiNoteOn(trackIndex: trackIndex, tick: absoluteTick, note: pitch))
                    trackNotes.append(pitch)
                    onsetCounts[absoluteTick, default: 0] += 1
                }
            }

            // Expose only tracks containing playable pitched material.
            if let minimum = trackNotes.min(), let maximum = trackNotes.max() {
                trackInfos.append(MidiTrackInfo(
                    index: trackIndex,
                    name: trackName,
                    noteCount: trackNotes.count,
                    minimumNote: minimum,
                    maximumNote: maximum,
                    chordOnsets: onsetCounts.values.filter { $0 > 1 }.count
                ))
            }
        }

        // Convert the final source tick through the complete global tempo map.
        let duration = milliseconds(forTick: maximumTick, ticksPerQuarter: division, tempos: tempos)
        // Rank shared transpositions by natural fit, then prefer the smallest absolute key change.
        let bestShift = (-6...6).max { left, right in
            let leftFit = naturalNoteFit(notes: notes, transpose: left)
            let rightFit = naturalNoteFit(notes: notes, transpose: right)
            if leftFit == rightFit { return abs(left) > abs(right) }
            return leftFit < rightFit
        } ?? 0
        // Return the fully parsed document and import-facing analysis.
        return MidiDocument(
            tracks: trackInfos,
            durationMs: duration,
            bestTranspose: bestShift,
            ticksPerQuarter: division,
            notes: notes,
            tempos: tempos
        )
    }

    // Measure this document's directly natural notes after one shared transpose.
    func naturalFit(transpose: Int, enabledTrackIndexes: Set<Int>? = nil) -> Double {
        // Restrict analysis to selected tracks when the UI supplies a selection.
        let selectedNotes = enabledTrackIndexes.map { selected in
            notes.filter { selected.contains($0.trackIndex) }
        } ?? notes
        // Reuse the parser's stable zero-to-one pitch-class measurement.
        return naturalNoteFit(notes: selectedNotes, transpose: transpose)
    }

    // Reduce selected source tracks into safe, source-timed Genshin lyre events.
    func makeScore(options: MidiImportOptions) -> [ImportedScoreEvent] {
        // Retain source order as a deterministic tie-breaker at equal timestamps.
        let selected = notes.enumerated().compactMap { index, source -> (Double, Int, String)? in
            // Ignore every unchecked source track.
            guard options.enabledTrackIndexes.contains(source.trackIndex) else { return nil }
            // Apply the shared key change and explicit missing-note policy.
            guard let key = lyreKey(for: source.note + options.transpose, policy: options.missingNotePolicy) else {
                return nil
            }
            // Convert the exact source tick using the document's tempo map.
            let onset = milliseconds(forTick: source.tick, ticksPerQuarter: ticksPerQuarter, tempos: tempos)
            // Return the sortable onset, source order, and mapped physical key.
            return (onset, index, key)
        }.sorted { left, right in
            // Order primarily by musical time and secondarily by stable source order.
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }
        // Return no events when every selected note was unavailable or every track was disabled.
        guard !selected.isEmpty else { return [] }

        // Accumulate final score events in chronological order.
        var score: [ImportedScoreEvent] = []
        // Anchor the current near-note group to its first source onset.
        var groupStart = selected[0].0
        // Preserve distinct mapped keys in their stable source order.
        var groupKeys: [String] = []
        // Remember the previously emitted group's onset for relative JSON delays.
        var previousStart = 0.0

        // Emit the current group using the shared three-key safety contract.
        func appendCurrentGroup() {
            // Do not emit an empty group after duplicate filtering.
            guard !groupKeys.isEmpty else { return }
            // Convert the source-onset gap into a nonnegative integer millisecond delay.
            let delay = max(0, Int((groupStart - previousStart).rounded()))
            // Keep no more than three distinct keys because the game and player contract share this cap.
            score.append(ImportedScoreEvent(delayMs: delay, keys: Array(groupKeys.prefix(3))))
            // Advance the relative-delay anchor to this emitted group.
            previousStart = groupStart
        }

        // Group all mapped notes by the selected onset tolerance.
        for (onset, _, key) in selected {
            // Start a new event when this onset falls outside the current group window.
            if onset - groupStart > Double(max(0, options.mergeToleranceMs)) {
                appendCurrentGroup()
                groupStart = onset
                groupKeys = []
            }
            // Remove octave-fold collisions without changing the remaining key order.
            if !groupKeys.contains(key) { groupKeys.append(key) }
        }
        // Emit the final accumulated onset group.
        appendCurrentGroup()
        // Return JSON-ready score events.
        return score
    }
}

// Map one shifted MIDI pitch onto the three visible natural-note lyre rows.
private func lyreKey(for sourcePitch: Int, policy: MissingNotePolicy) -> String? {
    // Define the seven natural pitch classes used by every row.
    let naturalClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
    // Begin from the globally shifted source pitch.
    var pitch = sourcePitch
    // Resolve unavailable black-key pitches only through the user's explicit policy.
    if !naturalClasses.contains(positiveModulo(pitch, 12)) {
        switch policy {
        case .skip:
            return nil
        case .down:
            repeat { pitch -= 1 } while !naturalClasses.contains(positiveModulo(pitch, 12))
        case .up:
            repeat { pitch += 1 } while !naturalClasses.contains(positiveModulo(pitch, 12))
        }
    }
    // Fold low pitches upward by octaves without changing their pitch class.
    while pitch < 48 { pitch += 12 }
    // Fold high pitches downward by octaves into the top visible row.
    while pitch > 83 { pitch -= 12 }
    // Pair the seven natural pitches in each octave with the game's physical row keys.
    let naturalOffsets = [0, 2, 4, 5, 7, 9, 11]
    let rowKeys = [Array("zxcvbnm"), Array("asdfghj"), Array("qwertyu")]
    // Derive the zero-based octave row within the 48-to-83 playable window.
    let row = (pitch - 48) / 12
    // Derive the natural-note position within that row.
    guard rowKeys.indices.contains(row), let column = naturalOffsets.firstIndex(of: positiveModulo(pitch, 12)) else {
        return nil
    }
    // Return the single physical key as a String for JSON and CoreGraphics playback.
    return String(rowKeys[row][column])
}

// Return a nonnegative modulo result for unusually low transposed MIDI pitches.
private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
    // Swift's remainder keeps the dividend sign, so normalise it into zero through divisor-minus-one.
    return ((value % divisor) + divisor) % divisor
}

// Measure the directly playable natural-note share after one shared key change.
private func naturalNoteFit(notes: [MidiNoteOn], transpose: Int) -> Double {
    // Avoid division by zero for metadata-only files.
    guard !notes.isEmpty else { return 0 }
    // Define the seven white-key pitch classes.
    let naturalClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
    // Count source notes whose shifted pitch class is natural.
    let playable = notes.filter { naturalClasses.contains(($0.note + transpose + 120) % 12) }.count
    // Return a stable zero-to-one ratio.
    return Double(playable) / Double(notes.count)
}

// Convert one absolute tick through an ordered, piecewise-constant tempo map.
private func milliseconds(forTick tick: Int, ticksPerQuarter: Int, tempos: [MidiTempoChange]) -> Double {
    // Collapse same-tick tempo messages so the last authored value becomes active.
    var collapsed: [Int: Int] = [:]
    for change in tempos { collapsed[change.tick] = change.microsecondsPerQuarter }
    // Traverse tempo changes in chronological order.
    let ordered = collapsed.sorted { $0.key < $1.key }
    // Integrate completed tick spans under their active tempo.
    var milliseconds = 0.0
    var previousTick = 0
    var activeTempo = 500_000
    for (changeTick, nextTempo) in ordered {
        // Stop inside the current span when the requested tick precedes this change.
        if tick <= changeTick {
            return milliseconds + Double(tick - previousTick) * Double(activeTempo) / Double(ticksPerQuarter) / 1_000
        }
        // Add the complete span before activating the next tempo.
        milliseconds += Double(changeTick - previousTick) * Double(activeTempo) / Double(ticksPerQuarter) / 1_000
        previousTick = changeTick
        activeTempo = nextTempo
    }
    // Convert the final span after the last tempo instruction.
    return milliseconds + Double(tick - previousTick) * Double(activeTempo) / Double(ticksPerQuarter) / 1_000
}
