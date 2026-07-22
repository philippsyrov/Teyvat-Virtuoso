// Import Foundation for raw generated MIDI data and process exit.
import Foundation

// Fail one exporter assertion with a readable terminal message.
func exportExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Evaluate exactly once before deciding whether to terminate.
    guard condition() else {
        // Write the explanation where the Python test harness can retain it.
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        // Stop with a failing process status.
        exit(1)
    }
}

// Validate that exported files are ordinary parseable MIDI rather than app-private JSON.
@main
struct EditableMidiExporterTests {
    // Run the minimal exported MIDI round trip.
    static func main() throws {
        // Create a chord followed by a delayed melody note across two lyre rows.
        let score = [ImportedScoreEvent(delayMs: 0, keys: ["a", "d"]), ImportedScoreEvent(delayMs: 500, keys: ["q"])]
        // Generate a standard file directly through the production exporter.
        let data = try EditableMidiExporter.makeFile(score: score)
        // Require the Standard MIDI header instead of a custom proprietary payload.
        exportExpect(Array(data.prefix(4)) == Array("MThd".utf8), "expected Standard MIDI header")
        // Parse the export through the same native MIDI reader used by Import Score.
        let document = try MidiDocument.parse(data: data)
        // Confirm the export retained one audible track and all three authored notes.
        exportExpect(document.tracks.count == 1, "expected one editable MIDI track")
        exportExpect(document.notes.count == 3, "expected exported chord and melody notes")
        // Print success for the Python verification wrapper.
        print("EditableMidiExporterTests passed")
    }
}
