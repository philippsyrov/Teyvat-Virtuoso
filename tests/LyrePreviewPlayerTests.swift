// Import Foundation for a tiny executable test harness.
import Foundation

// Fail the standalone test process at the first broken preview invariant.
func expectPreview(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Write the precise failed invariant to standard error.
    if !condition() { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
}

// Exercise score timing and pitch mapping without opening an audio device.
@main
struct LyrePreviewPlayerTests {
    // Run every deterministic preview-planner assertion.
    static func main() {
        // Keep a source lead-in, simultaneous chord, and later interval.
        let score = [ImportedScoreEvent(delayMs: 100, keys: ["z", "c"]), ImportedScoreEvent(delayMs: 200, keys: ["q"])]
        // Convert each event into one absolute-time generated chord.
        let events = LyrePreviewPlanner.events(score: score)
        // Preserve first onset and true simultaneous notes.
        expectPreview(events[0].timeMs == 100 && events[0].frequencies.count == 2, "expected timed chord")
        // Preserve subsequent score delay cumulatively.
        expectPreview(events[1].timeMs == 300, "expected cumulative schedule")
        // Keep low C and high C exactly one octave-row mapping apart.
        expectPreview(abs(LyrePreviewPlanner.frequency(for: "z")! - 130.8128) < 0.01, "expected C3")
        expectPreview(abs(LyrePreviewPlanner.frequency(for: "q")! - 523.2511) < 0.01, "expected C5")
        // Confirm success to the Python parent harness.
        print("LyrePreviewPlayerTests passed")
    }
}
