// Import AppKit for the native window, controls, file picker, and drag-and-drop destination.
import AppKit
// Import Foundation for JSON, files, timing, and background queues.
import Foundation
// Import CoreGraphics for true keyboard-down and keyboard-up events.
import CoreGraphics
// Import UniformTypeIdentifiers for non-deprecated MIDI file-picker filtering.
import UniformTypeIdentifiers

// Reuse the MIDI engine's JSON-safe score event throughout the app.
typealias AppScoreEvent = ImportedScoreEvent

// Keep the macOS virtual key codes for the 21 displayed Genshin lyre keys.
let appKeyCodes: [String: CGKeyCode] = [
    "q": 12, "w": 13, "e": 14, "r": 15, "t": 17, "y": 16, "u": 32,
    "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "h": 4, "j": 38,
    "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "n": 45, "m": 46,
]

// Keep scroll-document coordinates top-down so the first section appears at launch.
final class FlippedStackView: NSStackView {
    // Match ordinary document reading order instead of AppKit's default bottom-up coordinates.
    override var isFlipped: Bool { true }
}

// Present one obvious target for Finder MIDI files.
final class MidiDropView: NSView {
    // Deliver a validated dropped MIDI URL to the app delegate.
    var onFile: ((URL) -> Void)?
    // Keep the central instruction visible inside the custom view.
    private let label = NSTextField(labelWithString: "Drop a .mid or .midi file here")

    // Build the native drag destination once.
    override init(frame frameRect: NSRect) {
        // Initialise the base AppKit view.
        super.init(frame: frameRect)
        // Register for Finder file URLs exactly once.
        registerForDraggedTypes([.fileURL])
        // Use a rounded tinted panel instead of an invisible drop target.
        wantsLayer = true
        // Round the panel corners for a standard macOS card appearance.
        layer?.cornerRadius = 12
        // Draw a subtle border around the target.
        layer?.borderWidth = 1
        // Use the system accent colour for the border.
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
        // Use the normal control background so dark mode works automatically.
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        // Emphasise the instruction without making it look like a button.
        label.font = .systemFont(ofSize: 15, weight: .medium)
        // Centre the instruction within the drop panel.
        label.alignment = .center
        // Use secondary colour until a file is actively dragged over it.
        label.textColor = .secondaryLabelColor
        // Opt into Auto Layout for the label.
        label.translatesAutoresizingMaskIntoConstraints = false
        // Add the label to the custom card.
        addSubview(label)
        // Pin the label to the visual centre with safe horizontal padding.
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
        ])
    }

    // Prevent storyboard decoding because this app constructs every view in code.
    required init?(coder: NSCoder) { nil }

    // Accept only file drags containing one supported MIDI extension.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Highlight valid sources and reject every unrelated Finder item.
        guard midiURL(from: sender) != nil else { return [] }
        // Make the active drop state obvious.
        label.textColor = .controlAccentColor
        // Tell Finder this operation reads/copies the file without moving it.
        return .copy
    }

    // Remove active styling when the pointer leaves without dropping.
    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Restore the normal secondary instruction colour.
        label.textColor = .secondaryLabelColor
    }

    // Deliver a valid MIDI URL after the user releases the drag.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Restore the normal idle style immediately.
        label.textColor = .secondaryLabelColor
        // Require one supported file URL.
        guard let url = midiURL(from: sender) else { return false }
        // Hand the read-only URL to the importer.
        onFile?(url)
        // Confirm the drop was handled.
        return true
    }

    // Extract one local `.mid` or `.midi` file URL from a drag pasteboard.
    private func midiURL(from sender: NSDraggingInfo) -> URL? {
        // Read the standard Finder file URL pasteboard object.
        guard let value = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL else {
            return nil
        }
        // Compare extensions case-insensitively.
        let extensionName = value.pathExtension.lowercased()
        // Accept exactly the two common Standard MIDI extensions.
        return ["mid", "midi"].contains(extensionName) ? value : nil
    }
}

// Own playback state and keep musical timing off the AppKit main thread.
final class PlaybackController {
    // Let the window display status changes on the main queue.
    var onStatus: ((String) -> Void)?
    // Protect cancellation state shared by the UI and playback queue.
    private let lock = NSLock()
    // Remember whether Stop interrupted the active performance.
    private var cancelled = false

    // Load and begin one bundled score after the normal focus countdown.
    func play(_ song: Song, at speed: Double) {
        // Resolve the read-only bundled score before entering the common player.
        guard let score = loadBundledScore(song) else { return }
        // Use the same in-memory playback path as imported MIDI scores.
        play(score: score, title: song.title, at: speed)
    }

    // Begin an already-generated score after a five-second focus window.
    func play(score: [AppScoreEvent], title: String, at speed: Double) {
        // Ask macOS for Accessibility access before pretending playback can send keys.
        guard hasAccessibilityAccess else {
            setStatus("Accessibility permission is required. Enable Teyvat Virtuoso in System Settings, then reopen the app.")
            return
        }
        // Reject unsafe generated or saved events before any keyboard access.
        guard isSafe(score) else {
            setStatus("Unsafe or empty score: \(title).")
            return
        }
        // Clear a prior stop request before launching the new score.
        lock.lock()
        cancelled = false
        lock.unlock()
        // Tell the user exactly when and how fast playback will begin.
        setStatus("Open the instrument and click GeForce NOW — \(title) starts in 5 seconds at \(String(format: "%.0f", speed * 100))%.")
        // Move waiting and keyboard events off the app's UI loop.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Stop if the controller was released.
            guard let self else { return }
            // Give the user time to focus Genshin or GeForce NOW.
            guard self.wait(seconds: 5) else { return }
            // Play every saved event in chronological order.
            for event in score {
                // Keep every rest interruptible by Stop.
                guard self.wait(seconds: Double(event.delayMs) / 1_000 / speed) else { return }
                // Deliver all event keys as one true chord.
                self.playChord(event.keys)
            }
            // Confirm a normal ending only after the final note.
            self.setStatus("Performance complete: \(title).")
        }
    }

    // Check the actual process identity and let macOS show its standard permission prompt.
    private var hasAccessibilityAccess: Bool {
        // Use Apple's documented prompt option so the correct rebuilt app appears in Privacy settings.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        // Trust only the current signed app process, never a stale bundle with the same display name.
        return AXIsProcessTrustedWithOptions(options)
    }

    // Request a stop before the next key group.
    func stop() {
        // Set the shared cancellation flag under its lock.
        lock.lock()
        cancelled = true
        lock.unlock()
        // Update the window immediately.
        setStatus("Playback stopped.")
    }

    // Read one selected JSON score from the app Resources folder.
    private func loadBundledScore(_ song: Song) -> [AppScoreEvent]? {
        // Resolve generated scores from Application Support and public scores from the bundle.
        let url = song.userProvided == true
            ? UserScoreStore().scoreURL(for: song.file)
            : Bundle.main.url(forResource: song.file, withExtension: nil)
        // Require the exact resolved score file.
        guard let url else {
            setStatus("Missing bundled score: \(song.title).")
            return nil
        }
        // Decode the common score-event schema.
        guard let score = try? JSONDecoder().decode([AppScoreEvent].self, from: Data(contentsOf: url)) else {
            setStatus("Could not read \(song.title).")
            return nil
        }
        // Return the decoded score; common playback validates it.
        return score
    }

    // Confirm every event stays inside the app's keyboard safety contract.
    private func isSafe(_ score: [AppScoreEvent]) -> Bool {
        // Require at least one event and validate delay, size, and every key.
        return !score.isEmpty && score.allSatisfy {
            $0.delayMs >= 0 && !$0.keys.isEmpty && $0.keys.count <= 3 && $0.keys.allSatisfy { appKeyCodes[$0] != nil }
        }
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
        // Copy the protected value.
        let value = cancelled
        // Release the lock before returning.
        lock.unlock()
        // Report the copied state.
        return value
    }

    // Send one true chord: every key down first, then every key up.
    private func playChord(_ keys: [String]) {
        // Build system-style keyboard events for the focused game window.
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        // Press every note before releasing any one note.
        for key in keys {
            // Validation guarantees a matching virtual key code.
            CGEvent(keyboardEventSource: source, virtualKey: appKeyCodes[key]!, keyDown: true)?.post(tap: .cghidEventTap)
        }
        // Hold the shared chord long enough for streaming input to recognise it.
        Thread.sleep(forTimeInterval: 0.025)
        // Release notes only after the common hold.
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

// Build and own the complete native app window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Retain the live app window for the full application lifetime.
    private var window: NSWindow?
    // Store the bundled picker library.
    private var songs: [Song] = []
    // Store the currently imported MIDI document and its source filename.
    private var importedDocument: MidiDocument?
    private var importedTitle = "Imported MIDI"
    // Keep source track index to checkbox mappings.
    private var trackButtons: [Int: NSButton] = [:]
    // Store the native song selector.
    private let songPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store the timing selector shared by bundled and imported scores.
    private let speedPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store MIDI reduction controls.
    private let transposePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let policyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mergePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store visible descriptions and live status.
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let importSummaryLabel = NSTextField(wrappingLabelWithString: "No MIDI loaded yet.")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Choose a saved song or import a MIDI.")
    // Store the dynamic source track checkbox list.
    private let tracksStack = NSStackView()
    // Store actions whose enabled state follows the imported document.
    private lazy var playImportedButton = NSButton(title: "Play Imported — 5 second focus time", target: self, action: #selector(playImported))
    // Store the generated-score persistence action.
    private lazy var saveImportedButton = NSButton(title: "Save to Library", target: self, action: #selector(saveImported))
    // Own the local Application Support score store.
    private let userScoreStore = UserScoreStore()
    // Own the cancellable native keyboard player.
    private let player = PlaybackController()

    // Construct the app's single native window at launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load public bundled scores before filling the selector.
        songs = loadLibrary()
        // Create a useful instrument-workbench-sized window.
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Stop if AppKit did not retain the new window.
        guard let window = self.window else { return }
        // Give the window the project identity.
        window.title = "Teyvat Virtuoso"
        // Enforce a minimum size that keeps controls readable.
        window.minSize = NSSize(width: 660, height: 650)
        // Centre the first launch.
        window.center()
        // Build the vertically scrollable workbench content.
        window.contentView = makeContentView()
        // Reflect playback state in the bottom status line.
        player.onStatus = { [weak self] text in self?.statusLabel.stringValue = text }
        // Show and activate the app.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Build the full scrollable workbench UI.
    private func makeContentView() -> NSView {
        // Create the outer scroll view for long track lists and smaller screens.
        let scroll = NSScrollView()
        // Show a vertical scroller only when needed.
        scroll.hasVerticalScroller = true
        // Hide the decorative border around the full content.
        scroll.borderType = .noBorder
        // Create one main vertical layout stack.
        let stack = FlippedStackView()
        // Lay sections from top to bottom.
        stack.orientation = .vertical
        // Stretch wide controls to the available content width.
        stack.alignment = .leading
        // Use consistent macOS spacing between related controls.
        stack.spacing = 12
        // Add comfortable content margins.
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        // Give the document view a stable width; its height will come from intrinsic content.
        stack.frame = NSRect(x: 0, y: 0, width: 700, height: 0)

        // Add project title and purpose.
        stack.addArrangedSubview(makeHeading("Teyvat Virtuoso", size: 24))
        stack.addArrangedSubview(makeSecondaryLabel("Native MIDI-to-instrument performances for Genshin Impact on macOS."))
        // Add the prepared-score library section.
        stack.addArrangedSubview(makeHeading("Saved performances", size: 15))
        configureLibraryPicker()
        stack.addArrangedSubview(songPicker)
        subtitleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(makeSavedButtons())
        // Separate the library from the live importer.
        stack.addArrangedSubview(makeSeparator())
        // Add the native MIDI importer section.
        stack.addArrangedSubview(makeHeading("Import MIDI", size: 18))
        stack.addArrangedSubview(makeSecondaryLabel("Your MIDI stays local. Choose its tracks and mapping before any keys are sent."))
        // Add a visible native drag destination.
        let dropView = MidiDropView(frame: NSRect(x: 0, y: 0, width: 650, height: 92))
        dropView.onFile = { [weak self] url in self?.loadMidi(url) }
        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.widthAnchor.constraint(equalToConstant: 650).isActive = true
        dropView.heightAnchor.constraint(equalToConstant: 92).isActive = true
        stack.addArrangedSubview(dropView)
        // Add a normal file-picker alternative to dragging.
        stack.addArrangedSubview(NSButton(title: "Open MIDI…", target: self, action: #selector(openMidi)))
        // Show source analysis immediately below file selection.
        importSummaryLabel.textColor = .secondaryLabelColor
        importSummaryLabel.maximumNumberOfLines = 3
        importSummaryLabel.preferredMaxLayoutWidth = 650
        stack.addArrangedSubview(importSummaryLabel)
        // Label and configure the dynamic source tracks.
        stack.addArrangedSubview(makeHeading("Enabled tracks", size: 14))
        tracksStack.orientation = .vertical
        tracksStack.alignment = .leading
        tracksStack.spacing = 5
        tracksStack.addArrangedSubview(makeSecondaryLabel("Load a MIDI to inspect its musical tracks."))
        stack.addArrangedSubview(tracksStack)
        // Add the importer configuration grid.
        configureImportControls()
        stack.addArrangedSubview(makeImportGrid())
        // Add live imported-score actions.
        playImportedButton.isEnabled = false
        saveImportedButton.isEnabled = false
        stack.addArrangedSubview(makeImportedButtons())
        // Add the common live status line.
        stack.addArrangedSubview(makeSeparator())
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 650
        stack.addArrangedSubview(statusLabel)
        // Size the scroll document to its real controls so AppKit cannot stretch grid rows.
        stack.frame.size.height = stack.fittingSize.height
        // Let the scroll view own the completed document stack.
        scroll.documentView = stack
        // Return the ready root content view.
        return scroll
    }

    // Load the packaged public-domain manifest once.
    private func loadLibrary() -> [Song] {
        // Find and decode the bundled manifest.
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let library = try? JSONDecoder().decode(SongLibrary.self, from: Data(contentsOf: url)) else { return [] }
        // Merge read-only public entries with valid locally generated entries.
        return library.songs + userScoreStore.loadSongs()
    }

    // Create one section heading with a caller-selected size.
    private func makeHeading(_ text: String, size: CGFloat) -> NSTextField {
        // Create a non-editable label.
        let label = NSTextField(labelWithString: text)
        // Use semibold system typography.
        label.font = .systemFont(ofSize: size, weight: .semibold)
        // Return the ready heading.
        return label
    }

    // Create one dark-mode-safe explanatory label.
    private func makeSecondaryLabel(_ text: String) -> NSTextField {
        // Create a normal non-editable label.
        let label = NSTextField(labelWithString: text)
        // Use secondary system colour.
        label.textColor = .secondaryLabelColor
        // Return the ready label.
        return label
    }

    // Create a full-width visual section divider.
    private func makeSeparator() -> NSBox {
        // Use AppKit's standard separator line style.
        let separator = NSBox()
        separator.boxType = .separator
        // Keep the line aligned with the 650-point content width.
        separator.widthAnchor.constraint(equalToConstant: 650).isActive = true
        // Return the ready divider.
        return separator
    }

    // Fill the saved-song picker and connect selection changes.
    private func configureLibraryPicker() {
        // Add each manifest title in order.
        songPicker.addItems(withTitles: songs.map(\.title))
        // Route selection changes to the subtitle updater.
        songPicker.target = self
        songPicker.action = #selector(selectionChanged)
        // Show the first song detail immediately.
        updateSubtitle()
    }

    // Configure all deterministic import controls.
    private func configureImportControls() {
        // Offer every sensible shared key shift.
        transposePicker.addItems(withTitles: (-6...6).map { "\($0 >= 0 ? "+" : "")\($0) semitones" })
        // Default to no shift before a file recommends one.
        transposePicker.selectItem(at: 6)
        // Offer the three explicit chromatic-note policies.
        policyPicker.addItems(withTitles: ["Strict — skip black keys", "Snap black keys down", "Snap black keys up"])
        // Default to strict preservation.
        policyPicker.selectItem(at: 0)
        // Offer conservative near-onset chord windows.
        mergePicker.addItems(withTitles: ["Off", "15 ms", "25 ms", "40 ms"])
        // Use 25 ms because it matches the existing streaming-safe arrangements.
        mergePicker.selectItem(at: 2)
        // Offer musically modest speed changes around the authored timing.
        speedPicker.addItems(withTitles: ["Timing: relaxed 90%", "Timing: original 100%", "Timing: lively 110%"])
        // Preserve original timing by default.
        speedPicker.selectItem(at: 1)
    }

    // Build the labelled importer options grid.
    private func makeImportGrid() -> NSGridView {
        // Pair plain-language labels with their native popup controls.
        let grid = NSGridView(views: [
            [makeSecondaryLabel("Transpose"), transposePicker],
            [makeSecondaryLabel("Missing notes"), policyPicker],
            [makeSecondaryLabel("Merge nearby notes"), mergePicker],
            [makeSecondaryLabel("Playback timing"), speedPicker],
        ])
        // Align labels consistently.
        grid.column(at: 0).xPlacement = .trailing
        // Add breathing room between rows and columns.
        grid.rowSpacing = 7
        grid.columnSpacing = 12
        // Refuse surplus scroll-view height so the four option rows stay compact.
        grid.setContentHuggingPriority(.required, for: .vertical)
        // Refuse vertical compression that would overlap labels and popups.
        grid.setContentCompressionResistancePriority(.required, for: .vertical)
        // Return the complete option grid.
        return grid
    }

    // Build saved-library Play and Stop buttons.
    private func makeSavedButtons() -> NSStackView {
        // Create the horizontal action row.
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        // Add saved score playback.
        row.addArrangedSubview(NSButton(title: "Play Saved — 5 second focus time", target: self, action: #selector(playSelected)))
        // Add the common immediate stop action.
        row.addArrangedSubview(NSButton(title: "Stop", target: self, action: #selector(stopPlayback)))
        // Return the ready row.
        return row
    }

    // Build imported-score Play and Stop buttons.
    private func makeImportedButtons() -> NSStackView {
        // Create the horizontal action row.
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        // Add the live imported-score action.
        row.addArrangedSubview(playImportedButton)
        // Save only generated JSON key events, never the source MIDI.
        row.addArrangedSubview(saveImportedButton)
        // Add the common immediate stop action.
        row.addArrangedSubview(NSButton(title: "Stop", target: self, action: #selector(stopPlayback)))
        // Return the ready row.
        return row
    }

    // Open a native file picker for Standard MIDI files.
    @objc private func openMidi() {
        // Create one ordinary macOS open panel.
        let panel = NSOpenPanel()
        // Restrict selection to files rather than folders.
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Restrict visible choices to common MIDI extensions.
        panel.allowedContentTypes = ["mid", "midi"].compactMap { UTType(filenameExtension: $0) }
        // Load the chosen file after the sheet closes successfully.
        if panel.runModal() == .OK, let url = panel.url { loadMidi(url) }
    }

    // Parse and display one dropped or selected MIDI file.
    private func loadMidi(_ url: URL) {
        // Read and parse without copying the private source into app storage.
        do {
            // Parse the complete source through the native engine.
            let document = try MidiDocument.parse(data: Data(contentsOf: url))
            // Require at least one musical track before enabling playback.
            guard !document.tracks.isEmpty else {
                throw MidiParseError.malformedEvent("file with no musical note tracks")
            }
            // Store the parsed document only in memory.
            importedDocument = document
            // Use the source filename as the performance title.
            importedTitle = url.deletingPathExtension().lastPathComponent
            // Apply the engine's best shared key recommendation.
            transposePicker.selectItem(at: max(0, min(12, document.bestTranspose + 6)))
            // Rebuild one enabled checkbox per musical source track.
            rebuildTrackButtons(document.tracks)
            // Show honest source facts and natural-note fit.
            let totalNotes = document.tracks.reduce(0) { $0 + $1.noteCount }
            let fit = document.naturalFit(transpose: document.bestTranspose)
            importSummaryLabel.stringValue = "\(url.lastPathComponent) • \(formatDuration(document.durationMs)) • \(totalNotes) notes • \(document.tracks.count) musical tracks • \(String(format: "%.1f", fit * 100))% natural-note fit at \(signed(document.bestTranspose))"
            // Enable live conversion and playback.
            playImportedButton.isEnabled = true
            saveImportedButton.isEnabled = true
            // Confirm the safe read-only import.
            statusLabel.stringValue = "MIDI analysed locally. Review tracks and mapping, then play it."
        } catch {
            // Clear stale imported state after a failed parse.
            importedDocument = nil
            playImportedButton.isEnabled = false
            saveImportedButton.isEnabled = false
            // Show the parser's direct explanation.
            statusLabel.stringValue = error.localizedDescription
        }
    }

    // Replace the dynamic track controls after each successful import.
    private func rebuildTrackButtons(_ tracks: [MidiTrackInfo]) {
        // Remove previous checkbox views from both layout and hierarchy.
        for view in tracksStack.arrangedSubviews {
            tracksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // Clear stale source-index mappings.
        trackButtons = [:]
        // Add one enabled checkbox with useful track facts.
        for track in tracks {
            // Build a concise human-readable track label.
            let title = "\(track.name) — \(track.noteCount) notes, MIDI \(track.minimumNote)–\(track.maximumNote), \(track.chordOnsets) chord onsets"
            // Use a switch-style checkbox so selected tracks are obvious.
            let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            // Enable every musical track initially; the user can remove noisy parts.
            button.state = .on
            // Preserve the original track index outside AppKit's sequential rows.
            trackButtons[track.index] = button
            // Add the control to the visible list.
            tracksStack.addArrangedSubview(button)
        }
        // Grow the scroll document to the new intrinsic track-list height.
        if let stack = tracksStack.superview as? NSStackView {
            stack.frame.size.height = stack.fittingSize.height
        }
    }

    // Convert current controls into one deterministic score.
    private func importedScore() -> [AppScoreEvent]? {
        // Require an analysed document.
        guard let document = importedDocument else { return nil }
        // Keep only track indexes whose checkbox remains enabled.
        let enabled = Set(trackButtons.compactMap { index, button in button.state == .on ? index : nil })
        // Require at least one enabled source track.
        guard !enabled.isEmpty else {
            statusLabel.stringValue = "Enable at least one MIDI track."
            return nil
        }
        // Convert the visible popup choices into engine options.
        let options = MidiImportOptions(
            enabledTrackIndexes: enabled,
            transpose: transposePicker.indexOfSelectedItem - 6,
            missingNotePolicy: selectedMissingPolicy,
            mergeToleranceMs: selectedMergeTolerance
        )
        // Generate the common in-memory score schema.
        let score = document.makeScore(options: options)
        // Explain a mapping that removed every note.
        guard !score.isEmpty else {
            statusLabel.stringValue = "This mapping produced no playable natural notes. Try snapping or another transpose."
            return nil
        }
        // Return the safe generated score.
        return score
    }

    // Start the imported score through the common five-second player.
    @objc private func playImported() {
        // Generate the score from current visible options.
        guard let score = importedScore() else { return }
        // Play without writing or copying the source MIDI.
        player.play(score: score, title: importedTitle, at: selectedSpeed)
    }

    // Save the current generated reduction to the user's local picker library.
    @objc private func saveImported() {
        // Regenerate from the visible options so saved and previewed notes match.
        guard let score = importedScore() else { return }
        // Write generated JSON and refresh the picker.
        do {
            // Persist only score events and display metadata.
            let song = try userScoreStore.save(title: importedTitle, events: score)
            // Append the new entry to the live combined library.
            songs.append(song)
            // Rebuild picker titles without touching stored score files.
            songPicker.removeAllItems()
            songPicker.addItems(withTitles: songs.map(\.title))
            // Select the newly saved performance.
            songPicker.selectItem(at: songs.count - 1)
            // Show its generated-score description.
            updateSubtitle()
            // Confirm the local-only storage boundary.
            statusLabel.stringValue = "Saved generated score locally. The original MIDI was not copied."
        } catch {
            // Surface file-system failures without losing the in-memory MIDI.
            statusLabel.stringValue = "Could not save score: \(error.localizedDescription)"
        }
    }

    // Start the selected bundled score.
    @objc private func playSelected() {
        // Resolve the selected manifest row safely.
        let index = songPicker.indexOfSelectedItem
        // Begin only when that row exists.
        if songs.indices.contains(index) { player.play(songs[index], at: selectedSpeed) }
    }

    // Reflect saved-song selection changes beneath the picker.
    @objc private func selectionChanged() { updateSubtitle() }

    // Copy the selected saved arrangement subtitle into the window.
    private func updateSubtitle() {
        // Resolve the selected row safely.
        let index = songPicker.indexOfSelectedItem
        // Show a fallback only when the bundle has no manifest.
        subtitleLabel.stringValue = songs.indices.contains(index) ? songs[index].subtitle : "No bundled songs found."
    }

    // Stop either bundled or imported playback.
    @objc private func stopPlayback() { player.stop() }

    // Translate the mapping popup into the engine's explicit enum.
    private var selectedMissingPolicy: MissingNotePolicy {
        // Match the configured popup order.
        switch policyPicker.indexOfSelectedItem {
        case 1: return .down
        case 2: return .up
        default: return .skip
        }
    }

    // Translate the near-note popup into milliseconds.
    private var selectedMergeTolerance: Int {
        // Match the configured popup order.
        switch mergePicker.indexOfSelectedItem {
        case 1: return 15
        case 2: return 25
        case 3: return 40
        default: return 0
        }
    }

    // Translate the timing popup into one safe speed multiplier.
    private var selectedSpeed: Double {
        // Match the configured popup order.
        switch speedPicker.indexOfSelectedItem {
        case 0: return 0.90
        case 2: return 1.10
        default: return 1.00
        }
    }

    // Format a millisecond duration as minutes and zero-padded seconds.
    private func formatDuration(_ milliseconds: Double) -> String {
        // Round to the closest whole second for a compact UI summary.
        let seconds = Int((milliseconds / 1_000).rounded())
        // Return normal music-duration notation.
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    // Format a semitone shift with an explicit positive sign.
    private func signed(_ value: Int) -> String {
        // Make positive and zero recommendations visually unambiguous.
        return value >= 0 ? "+\(value)" : "\(value)"
    }
}

// Provide one explicit executable entry point when Swift compiles multiple source files.
@main
struct TeyvatVirtuosoApplication {
    // Create and run the normal native macOS application.
    static func main() {
        // Obtain AppKit's shared application object.
        let app = NSApplication.shared
        // Keep the delegate alive for the complete run-loop lifetime.
        let delegate = AppDelegate()
        // Attach the window-building delegate before starting the run loop.
        app.delegate = delegate
        // Enter the native macOS event loop.
        app.run()
    }
}
