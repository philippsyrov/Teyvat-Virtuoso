// Import Foundation for JSON decoding, files, timing, and command-line values.
import Foundation
// Import CoreGraphics for native macOS keyboard events with real simultaneous chords.
import CoreGraphics
// Import Darwin for process exit codes and microsecond sleeps.
import Darwin

// Model one timestamped group of lyre keys from the saved score JSON.
struct ScoreEvent: Codable {
    // Wait this many milliseconds after the preceding group.
    let delayMs: Int
    // Press all of these physical keys together.
    let keys: [String]
}

// Store Genshin's displayed lyre keys and their macOS virtual key codes.
let keyCodes: [String: CGKeyCode] = [
    "q": 12, "w": 13, "e": 14, "r": 15, "t": 17, "y": 16, "u": 32,
    "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "h": 4, "j": 38,
    "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "n": 45, "m": 46,
]

// Keep the active player's PID in a predictable temporary location for Stop Playback.
let pidFile = URL(fileURLWithPath: "/tmp/genshin-lyre-player.pid")

// Print an actionable error and return the shell-friendly invalid-input exit code.
func fail(_ message: String) -> Never {
    // Keep diagnostics on standard error so launchers show failures clearly.
    FileHandle.standardError.write(Data((message + "\n").utf8))
    // Use code two for an invalid launch request or score file.
    exit(2)
}

// Reject malformed scores before any key can be sent to the game.
func validate(_ score: [ScoreEvent]) -> String? {
    // Require at least one event so an empty file never looks successful.
    if score.isEmpty { return "score contains no events" }
    // Check each event independently for timing and keyboard safety.
    for event in score {
        // Negative waits have no useful musical meaning and break scheduling.
        if event.delayMs < 0 { return "delayMs must not be negative" }
        // Every beat must include at least one audible lyre note.
        if event.keys.isEmpty { return "event contains no keys" }
        // The saved arrangements deliberately limit chords to three notes.
        if event.keys.count > 3 { return "event contains more than three keys" }
        // Ensure every event key is a single supported lyre character.
        for key in event.keys {
            if key.count != 1 || keyCodes[key] == nil { return "unknown key: \(key)" }
        }
    }
    // A nil error means the entire score is safe to play.
    return nil
}

// Send one true chord: all keys down first, a short hold, then all keys up.
func playChord(_ keys: [String]) {
    // Build a keyboard event source for normal hardware-style events.
    guard let source = CGEventSource(stateID: .hidSystemState) else { fail("could not create keyboard event source") }
    // Press every note before releasing any note, preserving simultaneous chords.
    for key in keys {
        // Validation above guarantees this lookup succeeds.
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCodes[key]!, keyDown: true)!
        // Deliver the down event to whichever app the user focused during lead-in.
        event.post(tap: .cghidEventTap)
    }
    // Hold just long enough for GFN to register the group as a chord.
    usleep(25_000)
    // Release every note after the shared hold window ends.
    for key in keys.reversed() {
        // Validation above guarantees this lookup succeeds.
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCodes[key]!, keyDown: false)!
        // Deliver the matching key-up event through the same system tap.
        event.post(tap: .cghidEventTap)
    }
}

// Read optional flags and the required score path from the command line.
let arguments = Array(CommandLine.arguments.dropFirst())
// Let tests inspect validation without asking macOS to emit any keys.
let validateOnly = arguments.first == "--validate-only"
// Find an optional lead-in value so the Desktop launcher can give focus time.
let leadInIndex = arguments.firstIndex(of: "--lead-in")
// Read the lead-in seconds when supplied, otherwise start immediately.
let leadInSeconds = leadInIndex.flatMap { index in index + 1 < arguments.count ? Double(arguments[index + 1]) : nil } ?? 0
// Select the last non-flag argument as the JSON score path.
let scorePath = arguments.last(where: { !$0.hasPrefix("--") && Double($0) == nil })

// Require a readable source score.
guard let scorePath else { fail("usage: GenshinLyrePlayer [--validate-only] [--lead-in seconds] score.json") }
// Read the score data before doing any timing or keyboard work.
guard let scoreData = try? Data(contentsOf: URL(fileURLWithPath: scorePath)) else { fail("could not read score: \(scorePath)") }
// Decode the score schema exactly as saved by the arranger.
guard let score = try? JSONDecoder().decode([ScoreEvent].self, from: scoreData) else { fail("score is not valid JSON event data") }
// Stop at the boundary if the score does not meet the player contract.
if let problem = validate(score) { fail(problem) }
// Finish immediately in validation mode so tests never send a keyboard event.
if validateOnly { exit(0) }

// Record this process so the Desktop stop launcher can stop it from another Terminal window.
try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(to: pidFile, atomically: true, encoding: .utf8)
// Remove the PID marker on normal exit or when the process unwinds.
defer { try? FileManager.default.removeItem(at: pidFile) }
// Tell the player exactly what they need to do before the first note.
print("Open the Genshin lyre and click GeForce NOW. Starting in \(String(format: "%.1f", leadInSeconds)) seconds…")
// Leave the user enough time to return focus to the game.
Thread.sleep(forTimeInterval: leadInSeconds)
// Play every saved event at its score-written delay.
for event in score {
    // Convert the stored millisecond spacing into a normal time interval.
    Thread.sleep(forTimeInterval: Double(event.delayMs) / 1_000)
    // Send the chord together rather than pretending it is several separate notes.
    playChord(event.keys)
}
// Confirm completion in the Terminal window after the final note.
print("Performance complete.")
