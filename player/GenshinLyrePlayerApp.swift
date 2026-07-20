// Import AppKit for a small native macOS window without extra framework macros.
import AppKit
// Import Foundation for JSON, timing, and background queues.
import Foundation
// Import CoreGraphics for true keyboard-down and keyboard-up events.
import CoreGraphics

// Model one saved simultaneous key group.
struct AppScoreEvent: Codable {
    // Wait this many milliseconds before this key group.
    let delayMs: Int
    // Send all listed keys at the same moment.
    let keys: [String]
}

// Model one selector entry in the bundled song library.
struct Song: Codable {
    // Keep a stable picker identity.
    let id: String
    // Display the human-friendly song title.
    let title: String
    // Display a concise arrangement description.
    let subtitle: String
    // Locate the matching bundled JSON score.
    let file: String
}

// Model the small JSON wrapper around all available songs.
struct SongLibrary: Codable {
    // Preserve the curated picker order.
    let songs: [Song]
}

// Keep the macOS virtual key codes for the 21 displayed Genshin lyre keys.
let appKeyCodes: [String: CGKeyCode] = [
    "q": 12, "w": 13, "e": 14, "r": 15, "t": 17, "y": 16, "u": 32,
    "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "h": 4, "j": 38,
    "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "n": 45, "m": 46,
]

// Own playback state and keep the musical timing loop off the AppKit main thread.
final class PlaybackController {
    // Let the window display status changes on the main queue.
    var onStatus: ((String) -> Void)?
    // Protect cancellation state shared by the UI and playback queue.
    private let lock = NSLock()
    // Remember whether Stop has interrupted the active performance.
    private var cancelled = false

    // Begin a selected score after a five-second focus window.
    func play(_ song: Song, at speed: Double) {
        // Clear a prior stop request before launching the new selected song.
        lock.lock()
        cancelled = false
        lock.unlock()
        // Tell the player exactly what to do before events begin.
        setStatus("Open the lyre and click GeForce NOW — starting in 5 seconds at \(String(format: "%.0f", speed * 100))% speed.")
        // Move loading, waiting, and keyboard events off the app's UI loop.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Stop if the controller was released or the score cannot be loaded.
            guard let self, let score = self.loadScore(song) else { return }
            // Give the player time to focus the lyre in GFN.
            guard self.wait(seconds: 5) else { return }
            // Play every saved event in chronological score order.
            for event in score {
                // Keep every rest interruptible by Stop.
                guard self.wait(seconds: Double(event.delayMs) / 1_000 / speed) else { return }
                // Deliver all event keys as one true chord.
                self.playChord(event.keys)
            }
            // Confirm the normal ending only after the final note.
            self.setStatus("Performance complete.")
        }
    }

    // Request a stop before the next key group.
    func stop() {
        // Set the shared cancellation flag under its lock.
        lock.lock()
        cancelled = true
        lock.unlock()
        // Update the window immediately rather than waiting for the next rest check.
        setStatus("Playback stopped.")
    }

    // Read one selected JSON score and reject malformed data before playback.
    private func loadScore(_ song: Song) -> [AppScoreEvent]? {
        // Locate the score copied into the app bundle's Resources folder.
        guard let url = Bundle.main.url(forResource: song.file, withExtension: nil) else {
            setStatus("Missing bundled score: \(song.title).")
            return nil
        }
        // Decode the existing reusable event schema.
        guard let score = try? JSONDecoder().decode([AppScoreEvent].self, from: Data(contentsOf: url)) else {
            setStatus("Could not read \(song.title).")
            return nil
        }
        // Verify timing, chord size, and every physical Genshin key.
        guard !score.isEmpty, score.allSatisfy({ $0.delayMs >= 0 && !$0.keys.isEmpty && $0.keys.count <= 3 && $0.keys.allSatisfy { appKeyCodes[$0] != nil } }) else {
            setStatus("Unsafe score data for \(song.title).")
            return nil
        }
        // Return a fully safe score to the background player.
        return score
    }

    // Wait in tiny slices so Stop reacts during long rests and lead-in.
    private func wait(seconds: Double) -> Bool {
        // Calculate one fixed deadline for the requested duration.
        let deadline = Date().addingTimeInterval(seconds)
        // Keep checking cancellation until that deadline arrives.
        while Date() < deadline {
            // End before the next note if the user pressed Stop.
            if isCancelled { return false }
            // Sleep briefly without spinning a CPU core.
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Do not start a note exactly after a late Stop press.
        return !isCancelled
    }

    // Safely inspect the shared cancellation flag.
    private var isCancelled: Bool {
        // Take the lock before reading the state.
        lock.lock()
        // Copy the protected value into a local constant.
        let value = cancelled
        // Release the lock before returning to playback.
        lock.unlock()
        // Report the copied cancellation state.
        return value
    }

    // Send each event group as genuine concurrent keyboard presses.
    private func playChord(_ keys: [String]) {
        // Build system-style keyboard events for the focused game window.
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Press every note before releasing any one note.
        for key in keys {
            // Validation guarantees a matching virtual key code.
            CGEvent(keyboardEventSource: source, virtualKey: appKeyCodes[key]!, keyDown: true)?.post(tap: .cghidEventTap)
        }
        // Keep the shared chord held long enough for GFN to recognise it.
        Thread.sleep(forTimeInterval: 0.025)
        // Release notes only after the common short hold.
        for key in keys.reversed() {
            // Validation guarantees a matching virtual key code.
            CGEvent(keyboardEventSource: source, virtualKey: appKeyCodes[key]!, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    // Publish a status change through the UI's main queue.
    private func setStatus(_ text: String) {
        // Ensure AppKit controls are touched only on the main thread.
        DispatchQueue.main.async { self.onStatus?(text) }
    }
}

// Build and own the entire small app window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Retain the live app window for the full application lifetime.
    private var window: NSWindow?
    // Store the loaded picker library.
    private var songs: [Song] = []
    // Store the native menu-style song selector.
    private let songPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store the small source-timing speed selector.
    private let speedPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store the one-line song description.
    private let subtitleLabel = NSTextField(labelWithString: "")
    // Store live player instructions and completion state.
    private let statusLabel = NSTextField(wrappingLabelWithString: "Choose a song, then press Play.")
    // Own the cancellable native keyboard player.
    private let player = PlaybackController()

    // Construct the app's single native window at launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load manifest entries before filling the selector.
        songs = loadLibrary()
        // Create a normal resizable utility window.
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 285),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // Use the retained window while building its visible content.
        guard let window = self.window else { return }
        // Give the window an ordinary macOS title.
        window.title = "Genshin Lyre Player"
        // Center it so the player can immediately find the picker.
        window.center()
        // Create the simple vertical content layout.
        let stack = NSStackView()
        // Stack elements from top to bottom.
        stack.orientation = .vertical
        // Keep text and controls left-aligned.
        stack.alignment = .leading
        // Add modest spacing without turning the app into a dashboard.
        stack.spacing = 14
        // Keep a readable border around all controls.
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        // Add the title line.
        stack.addArrangedSubview(makeTitle())
        // Fill and add the song picker.
        configurePicker()
        stack.addArrangedSubview(songPicker)
        // Add a gentle timing choice without exposing raw MIDI-engine controls.
        configureSpeedPicker()
        stack.addArrangedSubview(speedPicker)
        // Display the selected song's short detail.
        subtitleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitleLabel)
        // Put Play and Stop side by side.
        stack.addArrangedSubview(makeButtons())
        // Add a subtle live status line.
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)
        // Use the stack as the full window content view.
        window.contentView = stack
        // Let status changes update the visible label.
        player.onStatus = { [weak self] text in self?.statusLabel.stringValue = text }
        // Make the window visible and active now.
        window.makeKeyAndOrderFront(nil)
        // Bring this local app forward without stealing GFN during playback later.
        NSApp.activate(ignoringOtherApps: true)
    }

    // Load the packaged manifest once from the app Resources folder.
    private func loadLibrary() -> [Song] {
        // Find the single manifest copied during installation.
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let library = try? JSONDecoder().decode(SongLibrary.self, from: Data(contentsOf: url)) else { return [] }
        // Return the curated song order.
        return library.songs
    }

    // Build the lightweight bold app title.
    private func makeTitle() -> NSTextField {
        // Create a non-editable title label.
        let label = NSTextField(labelWithString: "Genshin Lyre Player")
        // Use the standard prominent macOS font.
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        // Return the ready label.
        return label
    }

    // Fill the popup selector and connect selection changes.
    private func configurePicker() {
        // Add each manifest title to the menu in order.
        songPicker.addItems(withTitles: songs.map(\.title))
        // Route selection changes back to this app delegate.
        songPicker.target = self
        songPicker.action = #selector(selectionChanged)
        // Show the first song description immediately.
        updateSubtitle()
    }

    // Offer only musically useful speed changes around the source's intended pace.
    private func configureSpeedPicker() {
        // Keep the labels short enough for the deliberately tiny native window.
        speedPicker.addItems(withTitles: ["Timing: relaxed 90%", "Timing: original 100%", "Timing: lively 110%"])
        // Preserve the score's authored timing unless the player intentionally changes it.
        speedPicker.selectItem(at: 1)
    }

    // Build Play and Stop as the only action buttons.
    private func makeButtons() -> NSStackView {
        // Create a horizontal button row.
        let row = NSStackView()
        // Lay the buttons left to right.
        row.orientation = .horizontal
        // Add a small consistent gap.
        row.spacing = 10
        // Create the play action with its user-facing lead-in hint.
        let play = NSButton(title: "Play — 5 second focus time", target: self, action: #selector(playSelected))
        // Make Play the visually primary button.
        play.bezelStyle = .rounded
        // Create the immediate cancellation action.
        let stop = NSButton(title: "Stop", target: self, action: #selector(stopPlayback))
        // Add the actions to the row.
        row.addArrangedSubview(play)
        row.addArrangedSubview(stop)
        // Return the finished button row.
        return row
    }

    // Update details after a popup selection changes.
    @objc private func selectionChanged() {
        // Reflect the selected arrangement beneath the popup.
        updateSubtitle()
    }

    // Copy the selected manifest subtitle into the window.
    private func updateSubtitle() {
        // Resolve the selected row safely.
        let index = songPicker.indexOfSelectedItem
        // Use an empty string only if the app bundle has no library.
        subtitleLabel.stringValue = songs.indices.contains(index) ? songs[index].subtitle : "No bundled songs found."
    }

    // Start the selected score's five-second lead-in and playback.
    @objc private func playSelected() {
        // Resolve the currently selected song before starting playback.
        let index = songPicker.indexOfSelectedItem
        // Start only if the selected menu row matches a manifest entry.
        if songs.indices.contains(index) { player.play(songs[index], at: selectedSpeed) }
    }

    // Translate the three friendly picker options into one safe timing multiplier.
    private var selectedSpeed: Double {
        // Match the configured menu order; default to the composer-facing original timing.
        switch speedPicker.indexOfSelectedItem {
        case 0: return 0.90
        case 2: return 1.10
        default: return 1.00
        }
    }

    // Stop the active player before its next key group.
    @objc private func stopPlayback() {
        // Forward the explicit user request to the shared player.
        player.stop()
    }
}

// Create the normal macOS application object.
let app = NSApplication.shared
// Keep the delegate alive for the full app lifetime.
let delegate = AppDelegate()
// Attach the window-building delegate before the app run loop starts.
app.delegate = delegate
// Enter the native macOS event loop.
app.run()
