// Import AppKit for the native window, controls, file picker, and drag-and-drop destination.
import AppKit
// Import AVFoundation for the offline generated lyre Listen preview.
import AVFoundation
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

// Keep a scroll page's document as wide as the live visible pane during window resizing.
final class ResponsivePageScrollView: NSScrollView {
    // Recalculate the page document after AppKit lays out the changed clip view.
    override func layout() {
        // Let AppKit complete its normal scroll-view layout first.
        super.layout()
        // Stop safely before the page stack exists during initial construction.
        guard let documentView else { return }
        // Match the document width to the visible pane so labels can wrap instead of clipping.
        documentView.frame.size.width = contentView.bounds.width
        // Recalculate height after the new width changes wrapped label heights.
        documentView.frame.size.height = documentView.fittingSize.height
    }
}

// Remove the split-view separator while preserving the normal sidebar-and-content layout.
final class BorderlessSplitView: NSSplitView {
    // Give AppKit no drawable divider width between the two navigation panes.
    override var dividerThickness: CGFloat { 0 }
}

// Present one obvious target for Finder MIDI or Sky Music sheet files.
final class MidiDropView: NSView {
    // Deliver a validated dropped MIDI URL to the app delegate.
    var onFile: ((URL) -> Void)?
    // Keep the central instruction visible inside the custom view.
    private let label = NSTextField(labelWithString: "Drop a MIDI or Sky Music .txt/.json sheet here")

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

    // Accept only file drags containing one supported score extension.
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

    // Extract one local MIDI or Sky Music-sheet URL from a drag pasteboard.
    private func midiURL(from sender: NSDraggingInfo) -> URL? {
        // Read the standard Finder file URL pasteboard object.
        guard let value = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL else {
            return nil
        }
        // Compare extensions case-insensitively.
        let extensionName = value.pathExtension.lowercased()
        // Accept MIDI plus exported Sky Music JSON-sheet extensions.
        return ["mid", "midi", "txt", "json"].contains(extensionName) ? value : nil
    }
}

// Own playback state and keep musical timing off the AppKit main thread.
final class PlaybackController {
    // Let the window display status changes on the main queue.
    var onStatus: ((String) -> Void)?
    // Let card rows redraw their primary action when playback starts or stops.
    var onPlaybackChange: ((String?) -> Void)?
    // Protect cancellation state shared by the UI and playback queue.
    private let lock = NSLock()
    // Remember whether Stop interrupted the active performance.
    private var cancelled = false
    // Identify the active card while preventing an older queue from clearing a newer playback state.
    private var activeGeneration = 0

    // Load and begin one bundled score after the normal focus countdown.
    func play(_ song: Song, id: String, at speed: Double) {
        // Resolve the read-only bundled score before entering the common player.
        guard let score = loadBundledScore(song) else { return }
        // Use the same in-memory playback path as imported MIDI scores.
        play(score: score, title: song.title, id: id, at: speed)
    }

    // Begin an already-generated score after a five-second focus window.
    func play(score: [AppScoreEvent], title: String, id: String, at speed: Double) {
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
        // Clear a prior stop request and reserve one generation for this new score.
        lock.lock()
        cancelled = false
        activeGeneration += 1
        let generation = activeGeneration
        lock.unlock()
        // Mark the exact card active only after accessibility and score validation succeed.
        setActiveID(id)
        // Tell the user exactly when and how fast playback will begin.
        setStatus("Open the instrument and click GeForce NOW — \(title) starts in 5 seconds at \(String(format: "%.0f", speed * 100))%.")
        // Move waiting and keyboard events off the app's UI loop.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Stop if the controller was released.
            guard let self else { return }
            // Give the user time to focus Genshin or GeForce NOW.
            guard self.wait(seconds: 5) else {
                self.clearActiveID(for: generation)
                return
            }
            // Play every saved event in chronological order.
            for event in score {
                // Keep every rest interruptible by Stop.
                guard self.wait(seconds: Double(event.delayMs) / 1_000 / speed) else {
                    self.clearActiveID(for: generation)
                    return
                }
                // Deliver all event keys as one true chord.
                self.playChord(event.keys)
            }
            // Confirm a normal ending only after the final note.
            self.setStatus("Performance complete: \(title).")
            // Return the active card to Play only when this remains the newest queue.
            self.clearActiveID(for: generation)
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
        activeGeneration += 1
        lock.unlock()
        // Return every card to its ready action immediately.
        setActiveID(nil)
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

    // Publish a card identity change through AppKit's main queue.
    private func setActiveID(_ id: String?) {
        // Ensure row rebuilding always runs on the main thread.
        DispatchQueue.main.async { self.onPlaybackChange?(id) }
    }

    // Clear an old queue only when no newer score has replaced it.
    private func clearActiveID(for generation: Int) {
        // Check the generation under the same lock used by Stop.
        lock.lock()
        let isCurrent = generation == activeGeneration
        lock.unlock()
        // Leave a newer card alone when an older queue finishes late.
        if isCurrent { setActiveID(nil) }
    }
}

// Name the three separate jobs exposed by the native source-list sidebar.
private enum NavigationDestination: Int, CaseIterable {
    // Browse attributed arrangements without mixing them into personal storage.
    case community
    // Play and manage bundled or explicitly saved personal performances.
    case library
    // Analyse and reduce one local Standard MIDI file.
    case importMidi

    // Present concise sidebar labels in stable order.
    var title: String {
        // Match each destination to its user-facing name.
        switch self {
        case .community: return "Community Collection"
        case .library: return "My Library"
        case .importMidi: return "Import MIDI"
        }
    }

    // Use familiar system symbols without shipping decorative assets.
    var symbolName: String {
        // Match discovery, personal music, and local import concepts.
        switch self {
        case .community: return "music.note.list"
        case .library: return "heart.text.square"
        case .importMidi: return "square.and.arrow.down"
        }
    }
}

// Build and own the complete native app window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    // Retain the live app window for the full application lifetime.
    private var window: NSWindow?
    // Store only bundled public-domain and user-saved personal performances.
    private var songs: [Song] = []
    // Store metadata-only community entries separately from the personal library.
    private var communityCatalog: [CommunityCatalogEntry] = []
    // Store the search-filtered community rows currently visible.
    private var visibleCommunityEntries: [CommunityCatalogEntry] = []
    // Store the currently imported MIDI document and its source filename.
    private var importedDocument: MidiDocument?
    // Store a strict converted Sky Music sheet when no MIDI track controls apply.
    private var directImportedScore: [AppScoreEvent]?
    private var importedTitle = "Imported Score"
    private var importedFilename = "Imported MIDI"
    // Keep source track index to checkbox mappings.
    private var trackButtons: [Int: NSButton] = [:]
    // Store the native personal-song selector.
    private let songPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store the timing selector used for live imports and their automatically saved speed.
    private let speedPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store MIDI reduction controls.
    private let transposePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let policyPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mergePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    // Store visible descriptions and live status.
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let importSummaryLabel = NSTextField(wrappingLabelWithString: "No MIDI loaded yet.")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Ready.")
    // Retain the native sidebar and one replaceable content host.
    private let sidebarTable = NSTableView()
    private let contentContainer = NSView()
    // Retain the community search and row stack for local filtering and cache refreshes.
    private let communitySearchField = NSSearchField()
    // Let people select the original visual-site folder category before browsing scores.
    private let communityCategoryPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let communityRowsStack = NSStackView()
    // Render the public catalogue in bounded batches instead of creating hundreds of cards at launch.
    private var communityVisibleLimit = 50
    // Explain how many matching arrangements remain behind Load more.
    private let communityResultLabel = NSTextField(labelWithString: "")
    // Retain the personal-library card stack so hearts and playback state can redraw in place.
    private let libraryRowsStack = NSStackView()
    // Retain the collapsed advanced MIDI controls outside the main import hierarchy.
    private let advancedMappingStack = NSStackView()
    // Retain the advanced disclosure so its complete title cannot be compressed into an ellipsis.
    private lazy var advancedMappingDisclosure = NSButton(title: "Advanced mapping", target: self, action: #selector(toggleAdvancedMapping(_:)))
    // Store the dynamic source track checkbox list.
    private let tracksStack = NSStackView()
    // Store actions whose enabled state follows the imported document.
    private lazy var playImportedButton = NSButton(title: "Preview — 5 second focus time", target: self, action: #selector(playImported))
    // Store the generated-score persistence action.
    private lazy var saveImportedButton = NSButton(title: "Save to My Library", target: self, action: #selector(saveImported))
    // Store the selected local song's persistent favourite action.
    private lazy var favoriteButton = NSButton(title: "♡ Favourite", target: self, action: #selector(toggleFavorite))
    // Own the local Application Support score store.
    private let userScoreStore = UserScoreStore()
    // Own the separate attributed community cache.
    private let communityScoreStore = CommunityScoreStore()
    // Own persistent favourite identities shared by every visible score collection.
    private let favoriteStore = FavoriteStore()
    // Own the cancellable native keyboard player.
    private let player = PlaybackController()
    // Own generated local score listening without any keyboard events.
    private let previewPlayer = LyrePreviewPlayer()
    // Export visual pages through the source site's own JSON notation rules.
    private let visualSheetDownloader = VisualSheetDownloader()
    // Remember the one active generated-audio preview card.
    private var activePreviewID: String?
    // Remember the one active card whose primary action should read Stop.
    private var activePlaybackID: String?

    // Construct the app's single native window at launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate earlier local-only heart state before rendering shared favourite cards.
        migrateLegacyFavorites()
        // Load personal and metadata-only community libraries before constructing pages.
        songs = loadLibrary()
        communityCatalog = loadCommunityCatalog()
        visibleCommunityEntries = communityCatalog
        // Configure controls exactly once before pages retain them.
        configureLibraryPicker()
        configureImportControls()
        // Create a wider music-player window with room for a real sidebar.
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Stop if AppKit did not retain the new window.
        guard let window = self.window else { return }
        // Give the window the project identity.
        window.title = "Teyvat Virtuoso"
        // Remove the bright native separator so the title bar flows into the dark app content.
        window.titlebarSeparatorStyle = .none
        // Enforce a minimum size that keeps controls readable.
        window.minSize = NSSize(width: 780, height: 600)
        // Centre the first launch.
        window.center()
        // Give the native navigation shell an explicit edge-pinned window host.
        let windowHost = NSView()
        let rootView = makeContentView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        windowHost.addSubview(rootView)
        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: windowHost.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: windowHost.trailingAnchor),
            rootView.topAnchor.constraint(equalTo: windowHost.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: windowHost.bottomAnchor),
        ])
        window.contentView = windowHost
        // Reflect playback state in the bottom status line.
        player.onStatus = { [weak self] text in self?.statusLabel.stringValue = text }
        // Rebuild only lightweight visible cards whenever their primary action changes state.
        player.onPlaybackChange = { [weak self] id in
            self?.activePlaybackID = id
            self?.rebuildCommunityRows()
            self?.rebuildLibraryRows()
        }
        // Reflect local Listen activity independently from keyboard playback.
        previewPlayer.onStatus = { [weak self] text in self?.statusLabel.stringValue = text }
        previewPlayer.onPlaybackChange = { [weak self] id in
            self?.activePreviewID = id
            self?.rebuildCommunityRows()
            self?.rebuildLibraryRows()
        }
        // Show and activate the app.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Build a sidebar shell with one visible destination and a persistent footer.
    private func makeContentView() -> NSView {
        // Use an explicitly constrained root so the split view can never collapse to intrinsic width.
        let root = NSView()
        // Split navigation from the active page without drawing a dark rule between them.
        let splitView = BorderlessSplitView()
        splitView.isVertical = true
        splitView.translatesAutoresizingMaskIntoConstraints = false
        // Build and retain the source-list sidebar.
        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 205).isActive = true
        // Let the content host fill all remaining split-view space.
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(contentContainer)
        // Keep playback status and Stop visible across every destination.
        let footer = makePersistentFooter()
        root.addSubview(splitView)
        root.addSubview(footer)
        // Pin the navigation and footer to every edge instead of relying on intrinsic stack width.
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        // Select Community Collection on first launch.
        sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        showDestination(.community)
        return root
    }

    // Build the dignified native source-list sidebar.
    private func makeSidebar() -> NSView {
        // Put the source list inside a normal scrolling sidebar surface.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        // Use one simple column because icons and labels belong to each row view.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Navigation"))
        column.width = 190
        sidebarTable.addTableColumn(column)
        sidebarTable.headerView = nil
        sidebarTable.style = .sourceList
        sidebarTable.rowSizeStyle = .medium
        sidebarTable.dataSource = self
        sidebarTable.delegate = self
        scroll.documentView = sidebarTable
        return scroll
    }

    // Keep the playback state and emergency stop visible below every page.
    private func makePersistentFooter() -> NSView {
        // Use a subtle material-backed footer instead of another full page section.
        let footer = NSVisualEffectView()
        footer.material = .headerView
        footer.blendingMode = .withinWindow
        footer.state = .active
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        // Keep concise status without duplicating each card's Stop action.
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(statusLabel)
        // Keep Stop on the active score card instead of repeating it in this footer.
        footer.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            row.topAnchor.constraint(equalTo: footer.topAnchor),
            row.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
        ])
        return footer
    }

    // Return the three stable sidebar row count.
    func numberOfRows(in tableView: NSTableView) -> Int {
        // This delegate owns only the navigation source list.
        return NavigationDestination.allCases.count
    }

    // Build one native icon-and-label source-list row.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Require a valid stable destination raw value.
        guard let destination = NavigationDestination(rawValue: row) else { return nil }
        // Reuse or construct one ordinary table cell.
        let identifier = NSUserInterfaceItemIdentifier("NavigationCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier
        // Rebuild the tiny row cleanly because there are only three destinations.
        cell.subviews.forEach { $0.removeFromSuperview() }
        let icon = NSImageView(image: NSImage(systemSymbolName: destination.symbolName, accessibilityDescription: destination.title) ?? NSImage())
        let label = NSTextField(labelWithString: destination.title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let rowStack = NSStackView(views: [icon, label])
        rowStack.orientation = .horizontal
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            rowStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // Switch the single content host when sidebar selection changes.
    func tableViewSelectionDidChange(_ notification: Notification) {
        // Ignore transient empty selection and resolve a stable destination.
        guard let destination = NavigationDestination(rawValue: sidebarTable.selectedRow) else { return }
        showDestination(destination)
    }

    // Replace the visible page without stacking unrelated workflows together.
    private func showDestination(_ destination: NavigationDestination) {
        // Remove only the prior page from the dedicated host.
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        // Construct the selected page from current library and import state.
        let page: NSView
        switch destination {
        case .community: page = makeCommunityView()
        case .library: page = makeLibraryView()
        case .importMidi: page = makeImportView()
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            page.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    // Create one consistently padded scroll page for long content.
    private func makePageScroll(_ stack: FlippedStackView) -> NSScrollView {
        // Keep every destination independently scrollable.
        let scroll = ResponsivePageScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 30, right: 30)
        // Start with no assumed page width; the scroll view supplies the live visible width.
        stack.frame = NSRect(x: 0, y: 0, width: 0, height: 0)
        // Preserve intrinsic content height so option grids never stretch grotesquely.
        stack.frame.size.height = stack.fittingSize.height
        scroll.documentView = stack
        return scroll
    }

    // Keep one page control inside its already-attached reading column instead of a hard-coded width.
    private func constrainToPageColumn(_ view: NSView, in stack: NSStackView, horizontalInset: CGFloat = 60) {
        // Let the constraint system size the control after its owning page stack resizes.
        view.translatesAutoresizingMaskIntoConstraints = false
        // Constrain only views that share a hierarchy so AppKit never raises a launch-time exception.
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -horizontalInset).isActive = true
    }

    // Build the attributed on-demand arrangement browser.
    private func makeCommunityView() -> NSView {
        // Present discovery as its own calm page.
        let stack = FlippedStackView()
        stack.addArrangedSubview(makeHeading("Community Collection", size: 26))
        let introduction = makeSecondaryLabel("Hand-arranged music for limited-note instruments. Credits remain attached; songs download only when you choose them.")
        stack.addArrangedSubview(introduction)
        constrainToPageColumn(introduction, in: stack)
        // Offer one clean discovery handoff without copying the wider community library into this app.
        let browseAll = NSButton(title: "Browse all Sky Music sheets", target: self, action: #selector(openCommunityLibrary))
        stack.addArrangedSubview(browseAll)
        // Filter the curated catalog locally without another network request.
        communitySearchField.placeholderString = "Search arrangements"
        communitySearchField.target = self
        communitySearchField.action = #selector(filterCommunitySongs)
        stack.addArrangedSubview(communitySearchField)
        constrainToPageColumn(communitySearchField, in: stack)
        // Populate the original source folders once and filter cards by the selected category.
        communityCategoryPicker.removeAllItems()
        communityCategoryPicker.addItem(withTitle: "All categories")
        communityCategoryPicker.addItems(withTitles: Array(Set(communityCatalog.compactMap(\.category))).sorted())
        communityCategoryPicker.target = self
        communityCategoryPicker.action = #selector(filterCommunitySongs)
        stack.addArrangedSubview(communityCategoryPicker)
        // Show search-result size before any person asks the page to create more rows.
        communityResultLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(communityResultLabel)
        constrainToPageColumn(communityResultLabel, in: stack)
        // Rebuild only this page's rows after search or cache changes.
        communityRowsStack.orientation = .vertical
        communityRowsStack.alignment = .leading
        communityRowsStack.spacing = 10
        rebuildCommunityRows()
        stack.addArrangedSubview(communityRowsStack)
        constrainToPageColumn(communityRowsStack, in: stack)
        return makePageScroll(stack)
    }

    // Filter the curated catalog by title or credited arranger.
    @objc private func filterCommunitySongs() {
        // Normalise user text for a forgiving local contains search.
        let query = communitySearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedCategory = communityCategoryPicker.titleOfSelectedItem
        let matchingEntries = communityCatalog.filter {
            let textMatches = query.isEmpty || $0.title.lowercased().contains(query) || ($0.arranger?.lowercased().contains(query) ?? false)
            let categoryMatches = selectedCategory == nil || selectedCategory == "All categories" || $0.category == selectedCategory
            return textMatches && categoryMatches
        }
        // Keep filled hearts at the top even after a person searches the catalog.
        visibleCommunityEntries = favoriteFirst(matchingEntries, id: { self.communityFavoriteID(for: $0) })
        // Return to the small first batch whenever the query changes.
        communityVisibleLimit = 50
        rebuildCommunityRows()
    }

    // Replace the visible community cards from current search and cache state.
    private func rebuildCommunityRows() {
        // Remove old arranged rows from both layout and hierarchy.
        for view in communityRowsStack.arrangedSubviews {
            communityRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // Explain an empty local search directly.
        if visibleCommunityEntries.isEmpty {
            communityRowsStack.addArrangedSubview(makeSecondaryLabel("No arrangements match this search."))
            return
        }
        // Explain total matches without forcing AppKit to build every card at once.
        communityResultLabel.stringValue = "\(visibleCommunityEntries.count) arrangements · showing \(min(communityVisibleLimit, visibleCommunityEntries.count))"
        // Build only the current bounded batch of matching metadata rows.
        for (index, entry) in visibleCommunityEntries.prefix(communityVisibleLimit).enumerated() {
            let card = NSBox()
            card.boxType = .custom
            card.cornerRadius = 10
            card.borderWidth = 1
            card.borderColor = NSColor.separatorColor
            card.fillColor = NSColor.controlBackgroundColor
            let title = makeHeading(entry.title, size: 15)
            // Keep long song names inside the text column instead of competing with the action rail.
            title.maximumNumberOfLines = 1
            title.lineBreakMode = .byTruncatingTail
            let detailText = entry.durationSeconds.map { "\(formatDuration(Double($0) * 1_000)) · \(entry.creditLine)" } ?? entry.creditLine
            let details = makeSecondaryLabel(detailText)
            // Keep attribution on one clipped line so every card remains a stable compact height.
            details.maximumNumberOfLines = 1
            details.lineBreakMode = .byTruncatingTail
            let textStack = NSStackView(views: [title, details])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 4
            textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let isActive = activePlaybackID == communityFavoriteID(for: entry)
            let actionTitle = isActive ? "Stop" : (communityScoreStore.isCached(entry) ? "Play" : "Download")
            let action = NSButton(title: actionTitle, target: self, action: #selector(communityPrimaryAction(_:)))
            action.tag = index
            // Keep the primary action aligned across rows even when its label changes to Download.
            action.widthAnchor.constraint(equalToConstant: 92).isActive = true
            if actionTitle == "Play" { action.keyEquivalent = "\r" }
            let source = NSButton(title: "Open Source", target: self, action: #selector(openCommunitySource(_:)))
            source.tag = index
            source.bezelStyle = .inline
            // Reserve one stable width for the source action beside every primary action.
            source.widthAnchor.constraint(equalToConstant: 140).isActive = true
            // Show the shared favourite heart inside the same fixed trailing card rail.
            let heart = NSButton(title: "♥", target: self, action: #selector(toggleCommunityFavorite(_:)))
            heart.tag = index
            heart.widthAnchor.constraint(equalToConstant: 36).isActive = true
            heart.bezelStyle = .inline
            heart.contentTintColor = favoriteStore.favoriteIDs().contains(communityFavoriteID(for: entry)) ? .systemRed : .secondaryLabelColor
            // Let Listen preview mapped local audio without sending keyboard events to Genshin.
            let isPreviewing = activePreviewID == communityFavoriteID(for: entry)
            let listen = NSButton(title: isPreviewing ? "Stop" : "Listen", target: self, action: #selector(communityListenAction(_:)))
            listen.tag = index
            listen.widthAnchor.constraint(equalToConstant: 70).isActive = true
            // Offer local cache cleanup only after this exact score was downloaded.
            let removeDownload = NSButton(title: "•••", target: self, action: #selector(communityMoreAction(_:)))
            removeDownload.tag = index
            removeDownload.widthAnchor.constraint(equalToConstant: 36).isActive = true
            removeDownload.isHidden = !communityScoreStore.isCached(entry)
            let actions = NSStackView(views: [source, heart, removeDownload, listen, action])
            actions.orientation = .horizontal
            actions.spacing = 8
            actions.setContentCompressionResistancePriority(.required, for: .horizontal)
            // Let this empty view absorb spare room and keep the action rail pinned to the trailing edge.
            let actionSpacer = NSView()
            actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [textStack, actionSpacer, actions])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 16
            row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
            row.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                row.topAnchor.constraint(equalTo: card.topAnchor),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
            communityRowsStack.addArrangedSubview(card)
            constrainToPageColumn(card, in: communityRowsStack, horizontalInset: 0)
        }
        // Offer another bounded batch only when matching rows remain hidden.
        if visibleCommunityEntries.count > communityVisibleLimit {
            let loadMore = NSButton(title: "Load more", target: self, action: #selector(loadMoreCommunityRows(_:)))
            communityRowsStack.addArrangedSubview(loadMore)
            constrainToPageColumn(loadMore, in: communityRowsStack, horizontalInset: 0)
        }
        // Resize the active community document after filtering or caching.
        if let pageStack = communityRowsStack.superview as? NSStackView {
            pageStack.frame.size.height = pageStack.fittingSize.height
        }
    }

    // Reveal one more small batch without changing search or favourite ordering.
    @objc private func loadMoreCommunityRows(_ sender: NSButton) {
        // Increase the rendering limit by one stable page size.
        communityVisibleLimit += 50
        // Rebuild only the visible community-card stack.
        rebuildCommunityRows()
    }

    // Listen to a cached or freshly downloaded community score locally.
    @objc private func communityListenAction(_ sender: NSButton) {
        // Resolve the rendered row safely.
        guard visibleCommunityEntries.indices.contains(sender.tag) else { return }
        let entry = visibleCommunityEntries[sender.tag]
        // Stop only this row's generated audio when Listen already owns it.
        if activePreviewID == communityFavoriteID(for: entry) { previewPlayer.stop(); return }
        // Require an explicit download before local previewing a community arrangement.
        guard let score = communityScoreStore.cachedScore(for: entry) else {
            statusLabel.stringValue = "Download \(entry.title) before listening to it."
            return
        }
        // Avoid overlapping synthetic sound with live keyboard playback.
        player.stop()
        previewPlayer.play(score: score, title: entry.title, id: communityFavoriteID(for: entry))
    }

    // Confirm removal of one downloaded conversion without changing its remote catalogue entry.
    @objc private func communityMoreAction(_ sender: NSButton) {
        // Resolve the exact cached card before showing any destructive confirmation.
        guard visibleCommunityEntries.indices.contains(sender.tag) else { return }
        let entry = visibleCommunityEntries[sender.tag]
        // Make the local-only deletion boundary visible before performing it.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove downloaded score?"
        alert.informativeText = "This removes only the local copy of \(entry.title). It stays listed and can be downloaded again later."
        alert.addButton(withTitle: "Remove Download")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            // Stop active modes before deleting the exact locally converted score.
            if activePlaybackID == communityFavoriteID(for: entry) { player.stop() }
            if activePreviewID == communityFavoriteID(for: entry) { previewPlayer.stop(silent: true) }
            try communityScoreStore.remove(entry: entry)
            statusLabel.stringValue = "Removed local download for \(entry.title)."
            rebuildCommunityRows()
        } catch {
            statusLabel.stringValue = "Could not remove \(entry.title): \(error.localizedDescription)"
        }
    }

    // Download an uncached arrangement or play its already validated local conversion.
    @objc private func communityPrimaryAction(_ sender: NSButton) {
        // Resolve the visible row rather than an unfiltered catalog index.
        guard visibleCommunityEntries.indices.contains(sender.tag) else { return }
        let entry = visibleCommunityEntries[sender.tag]
        // Let the active row stop its own playback without forcing a footer click.
        if activePlaybackID == communityFavoriteID(for: entry) {
            stopPlayback()
            return
        }
        // Play a validated local cache immediately when available.
        if let score = communityScoreStore.cachedScore(for: entry) {
            previewPlayer.stop(silent: true)
            player.play(score: score, title: entry.title, id: communityFavoriteID(for: entry), at: 1.00)
            return
        }
        // Export categorised visual sheets with the source website's own JSON rules.
        if let source = entry.visualSheetURL, let pageURL = URL(string: source) {
            sender.isEnabled = false
            statusLabel.stringValue = "Downloading \(entry.title)…"
            visualSheetDownloader.download(from: pageURL) { [weak self, weak sender] result in
                // Return the web extraction result to AppKit's main queue before changing UI.
                DispatchQueue.main.async {
                    guard let self else { return }
                    sender?.isEnabled = true
                    do {
                        let data = try result.get()
                        let source = try CommunitySourceSong.decodeResponse(data)
                        let score = try source.makeScore()
                        try self.communityScoreStore.cache(entry: entry, score: score)
                        self.statusLabel.stringValue = "Downloaded \(entry.title). It is cached locally and ready to play."
                        self.rebuildCommunityRows()
                    } catch {
                        self.statusLabel.stringValue = "Could not download \(entry.title): \(error.localizedDescription)"
                    }
                }
            }
            return
        }
        // Construct an encoded query without interpolating the remote filename into a path.
        var components = URLComponents(string: "https://sky-music.herokuapp.com/api/songs")!
        components.queryItems = [URLQueryItem(name: "get", value: entry.remoteFile)]
        guard let url = components.url else {
            statusLabel.stringValue = "Could not create the community download URL."
            return
        }
        sender.isEnabled = false
        statusLabel.stringValue = "Downloading \(entry.title)…"
        // Fetch only after explicit user action; personal library use remains offline.
        URLSession.shared.dataTask(with: url) { [weak self, weak sender] data, _, error in
            // Return all UI work to AppKit's main queue.
            DispatchQueue.main.async {
                guard let self else { return }
                sender?.isEnabled = true
                do {
                    // Surface transport failure before attempting to decode an empty body.
                    if let error { throw error }
                    guard let data else { throw CommunityLibraryError.emptyResponse }
                    // Validate and convert untrusted remote note data before persistence.
                    let source = try CommunitySourceSong.decodeResponse(data)
                    let score = try source.makeScore()
                    try self.communityScoreStore.cache(entry: entry, score: score)
                    self.statusLabel.stringValue = "Downloaded \(entry.title). It is cached locally and ready to play."
                    self.rebuildCommunityRows()
                } catch {
                    // Preserve any older valid cache and show a direct failure message.
                    self.statusLabel.stringValue = "Could not download \(entry.title): \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    // Open the selected arrangement's visible upstream source page.
    @objc private func openCommunitySource(_ sender: NSButton) {
        // Resolve the exact currently visible entry.
        guard visibleCommunityEntries.indices.contains(sender.tag),
              let url = URL(string: visibleCommunityEntries[sender.tag].sourceURL) else { return }
        // Hand the normal HTTPS link to the user's default browser.
        NSWorkspace.shared.open(url)
    }

    // Open the complete community library only when the person explicitly asks to browse it.
    @objc private func openCommunityLibrary() {
        // Use the maintained public library page rather than copying any community score data.
        guard let url = URL(string: "https://sky-music.github.io/") else { return }
        // Hand browser navigation to the person's normal default browser.
        NSWorkspace.shared.open(url)
    }

    // Toggle one community card's persistent shared heart and rebuild its favourite-first order.
    @objc private func toggleCommunityFavorite(_ sender: NSButton) {
        // Resolve the exact visible card rather than the unfiltered catalog order.
        guard visibleCommunityEntries.indices.contains(sender.tag) else { return }
        // Capture the stable identity before sorting changes the visible index.
        let entry = visibleCommunityEntries[sender.tag]
        let id = communityFavoriteID(for: entry)
        // Flip the state from the latest persisted manifest.
        let isFavorite = favoriteStore.favoriteIDs().contains(id)
        do {
            // Persist the new state before changing the row order.
            try favoriteStore.setFavorite(id, isFavorite: !isFavorite)
            // Re-sort the complete catalog and current search results around the new heart state.
            communityCatalog = favoriteFirst(communityCatalog, id: { self.communityFavoriteID(for: $0) })
            filterCommunitySongs()
            // Confirm the small local preference change without implying a remote upload.
            statusLabel.stringValue = isFavorite ? "Removed from favourites." : "Added to favourites."
        } catch {
            // Keep the existing order when the local manifest write fails.
            statusLabel.stringValue = "Could not update favourite: \(error.localizedDescription)"
        }
    }

    // Build the personal-only saved performance page.
    private func makeLibraryView() -> NSView {
        // Keep bundled public-domain and user-generated performances together but remote songs out.
        let stack = FlippedStackView()
        stack.addArrangedSubview(makeHeading("My Library", size: 26))
        let introduction = makeSecondaryLabel("Your saved performances stay on this Mac. Community downloads remain in their own collection.")
        stack.addArrangedSubview(introduction)
        constrainToPageColumn(introduction, in: stack)
        // Reuse the same compact, full-width card language as Community Collection.
        libraryRowsStack.orientation = .vertical
        libraryRowsStack.alignment = .leading
        libraryRowsStack.spacing = 10
        rebuildLibraryRows()
        stack.addArrangedSubview(libraryRowsStack)
        constrainToPageColumn(libraryRowsStack, in: stack)
        // Keep destructive local-library maintenance available without competing with every song card.
        let actions = NSPopUpButton(frame: .zero, pullsDown: true)
        actions.addItem(withTitle: "•••")
        actions.addItem(withTitle: "Clear Imported Library…")
        actions.item(at: 1)?.target = self
        actions.item(at: 1)?.action = #selector(clearImportedLibrary)
        stack.addArrangedSubview(actions)
        return makePageScroll(stack)
    }

    // Rebuild every personal card after a favourite, save, clear, or playback-state change.
    private func rebuildLibraryRows() {
        // Remove old cards from both layout and hierarchy before replacing their actions.
        for view in libraryRowsStack.arrangedSubviews {
            libraryRowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // Explain an unexpected empty personal library without leaving a blank page.
        guard !songs.isEmpty else {
            libraryRowsStack.addArrangedSubview(makeSecondaryLabel("No saved performances yet. Import a MIDI to add one."))
            return
        }
        // Build one favourite-aware personal card per bundled or locally generated score.
        for (index, song) in songs.enumerated() {
            // Draw the same restrained rounded card used for a community arrangement.
            let card = NSBox()
            card.boxType = .custom
            card.cornerRadius = 10
            card.borderWidth = 1
            card.borderColor = NSColor.separatorColor
            card.fillColor = NSColor.controlBackgroundColor
            // Keep title and description inside the text column before the action rail.
            let title = makeHeading(song.title, size: 15)
            title.maximumNumberOfLines = 1
            title.lineBreakMode = .byTruncatingTail
            let details = makeSecondaryLabel(song.subtitle)
            details.maximumNumberOfLines = 1
            details.lineBreakMode = .byTruncatingTail
            let textStack = NSStackView(views: [title, details])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 4
            textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // Change only the currently playing score's primary action into Stop.
            let isActive = activePlaybackID == libraryFavoriteID(for: song)
            let actionTitle = isActive ? "Stop" : "Play"
            let action = NSButton(title: actionTitle, target: self, action: #selector(libraryPrimaryAction(_:)))
            action.tag = index
            action.widthAnchor.constraint(equalToConstant: 92).isActive = true
            if actionTitle == "Play" { action.keyEquivalent = "\r" }
            // Place the filled or outlined heart directly beside that primary action.
            let heart = NSButton(title: "♥", target: self, action: #selector(toggleLibraryFavorite(_:)))
            heart.tag = index
            heart.widthAnchor.constraint(equalToConstant: 36).isActive = true
            heart.bezelStyle = .inline
            heart.contentTintColor = favoriteStore.favoriteIDs().contains(libraryFavoriteID(for: song)) ? .systemRed : .secondaryLabelColor
            // Give local scores the same keyboard-free Listen affordance as community rows.
            let isPreviewing = activePreviewID == libraryFavoriteID(for: song)
            let listen = NSButton(title: isPreviewing ? "Stop" : "Listen", target: self, action: #selector(libraryListenAction(_:)))
            listen.tag = index
            listen.widthAnchor.constraint(equalToConstant: 70).isActive = true
            let actions = NSStackView(views: [heart, listen, action])
            actions.orientation = .horizontal
            actions.spacing = 8
            actions.setContentCompressionResistancePriority(.required, for: .horizontal)
            // Absorb spare width so the heart and play control stay pinned to the trailing edge.
            let actionSpacer = NSView()
            actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [textStack, actionSpacer, actions])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 16
            row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
            row.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                row.topAnchor.constraint(equalTo: card.topAnchor),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            ])
            libraryRowsStack.addArrangedSubview(card)
            constrainToPageColumn(card, in: libraryRowsStack, horizontalInset: 0)
        }
        // Recalculate the page document after a favourite sorting or playback action.
        if let pageStack = libraryRowsStack.superview as? NSStackView {
            pageStack.frame.size.height = pageStack.fittingSize.height
        }
    }

    // Build the local MIDI import page with technical controls collapsed by default.
    private func makeImportView() -> NSView {
        // Present import as a separate focused workflow.
        let stack = FlippedStackView()
        stack.addArrangedSubview(makeHeading("Import Score", size: 26))
        let introduction = makeSecondaryLabel("MIDI and Sky Music sheets stay local. Review tracks or import a timed sheet before previewing or saving.")
        stack.addArrangedSubview(introduction)
        constrainToPageColumn(introduction, in: stack)
        // Add a large but bounded native drag destination.
        let dropView = MidiDropView(frame: NSRect(x: 0, y: 0, width: 620, height: 112))
        dropView.onFile = { [weak self] url in self?.loadScore(url) }
        dropView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let sourceCard = makeImportCard(dropView)
        stack.addArrangedSubview(sourceCard)
        constrainToPageColumn(sourceCard, in: stack)
        // Keep file selection aligned to the same full-width source card.
        let openMidiButton = NSButton(title: "Open Score…", target: self, action: #selector(openMidi))
        stack.addArrangedSubview(openMidiButton)
        // Show concise source analysis before technical reduction controls.
        importSummaryLabel.textColor = .secondaryLabelColor
        importSummaryLabel.maximumNumberOfLines = 0
        importSummaryLabel.lineBreakMode = .byWordWrapping
        let summaryCard = makeImportCard(importSummaryLabel)
        stack.addArrangedSubview(summaryCard)
        constrainToPageColumn(summaryCard, in: stack)
        // Group the track heading and checkboxes in one full-width card.
        let tracksContent = NSStackView()
        tracksContent.orientation = .vertical
        tracksContent.alignment = .leading
        tracksContent.spacing = 10
        tracksContent.addArrangedSubview(makeHeading("Enabled tracks", size: 15))
        tracksStack.orientation = .vertical
        tracksStack.alignment = .leading
        tracksStack.spacing = 7
        if tracksStack.arrangedSubviews.isEmpty {
            tracksStack.addArrangedSubview(makeSecondaryLabel("Load a MIDI to inspect its musical tracks."))
        }
        tracksContent.addArrangedSubview(tracksStack)
        let tracksCard = makeImportCard(tracksContent)
        stack.addArrangedSubview(tracksCard)
        constrainToPageColumn(tracksCard, in: stack)
        // Keep mapping controls permanently visible so the old disclosure cannot collapse into `A...`.
        advancedMappingStack.orientation = .vertical
        advancedMappingStack.alignment = .leading
        advancedMappingStack.spacing = 10
        if advancedMappingStack.arrangedSubviews.isEmpty {
            advancedMappingStack.addArrangedSubview(makeHeading("Mapping settings", size: 15))
            advancedMappingStack.addArrangedSubview(makeImportGrid())
        }
        advancedMappingStack.isHidden = false
        let advancedMappingCard = makeImportCard(advancedMappingStack)
        stack.addArrangedSubview(advancedMappingCard)
        constrainToPageColumn(advancedMappingCard, in: stack)
        playImportedButton.isEnabled = importedDocument != nil
        saveImportedButton.isEnabled = importedDocument != nil
        let actionCard = makeImportCard(makeImportedButtons())
        stack.addArrangedSubview(actionCard)
        constrainToPageColumn(actionCard, in: stack)
        return makePageScroll(stack)
    }

    // Wrap one importer section in the same full-width rounded card language as every score row.
    private func makeImportCard(_ content: NSView) -> NSBox {
        // Create one subtle card whose border works in light and dark mode.
        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 10
        card.borderWidth = 1
        card.borderColor = NSColor.separatorColor
        card.fillColor = NSColor.controlBackgroundColor
        // Let the supplied section control or stack fill the card with consistent breathing room.
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        // Return the complete full-width import card.
        return card
    }

    // Reveal or hide advanced MIDI reduction controls without changing their values.
    @objc private func toggleAdvancedMapping(_ sender: NSButton) {
        // Mirror the disclosure state exactly.
        advancedMappingStack.isHidden = sender.state != .on
        // Recompute the import document height after the visibility change.
        if let pageStack = advancedMappingStack.superview as? NSStackView {
            pageStack.frame.size.height = pageStack.fittingSize.height
        }
    }

    // Load the packaged public-domain manifest once.
    private func loadLibrary() -> [Song] {
        // Find and decode the bundled manifest.
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let library = try? JSONDecoder().decode(SongLibrary.self, from: Data(contentsOf: url)) else { return [] }
        // Merge read-only public entries with valid locally generated entries.
        return favoriteFirst(library.songs + userScoreStore.loadSongs(), id: { self.libraryFavoriteID(for: $0) })
    }

    // Keep every current local favourite when moving from the old per-song flag to shared hearts.
    private func migrateLegacyFavorites() {
        // Read the existing local manifest before cards ask the shared store for its IDs.
        for song in userScoreStore.loadSongs() where song.isFavorite {
            // Preserve each persisted local favourite without changing its generated score.
            try? favoriteStore.setFavorite(libraryFavoriteID(for: song), isFavorite: true)
        }
    }

    // Decode a personal score for Listen using the same bundle/Application Support boundary as playback.
    private func loadScoreForListening(_ song: Song) -> [AppScoreEvent]? {
        // Resolve user-generated scores locally and bundled public scores from Resources.
        let url = song.userProvided == true ? userScoreStore.scoreURL(for: song.file) : Bundle.main.url(forResource: song.file, withExtension: nil)
        // Decode only the ordinary validated score-event schema.
        guard let url, let score = try? JSONDecoder().decode([AppScoreEvent].self, from: Data(contentsOf: url)), !score.isEmpty else { return nil }
        // Return events for generated audio; this path does not request Accessibility access.
        return score
    }

    // Namespace every personal score identity away from metadata-only community entries.
    private func libraryFavoriteID(for song: Song) -> String {
        // Use the stable manifest identity rather than a mutable display title.
        return "library:\(song.id)"
    }

    // Namespace every community identity away from bundled and imported scores.
    private func communityFavoriteID(for entry: CommunityCatalogEntry) -> String {
        // Use the repository-owned catalog ID rather than its visible title.
        return "community:\(entry.id)"
    }

    // Sort cards with favourites first while keeping original order among equal heart states.
    private func favoriteFirst<T>(_ items: [T], id: (T) -> String) -> [T] {
        // Read the current small manifest once for this complete ordering pass.
        let favorites = favoriteStore.favoriteIDs()
        // Retain order explicitly because Swift sorting does not promise stability.
        return items.enumerated().sorted { left, right in
            // Check each item's persistent shared favourite state.
            let leftIsFavorite = favorites.contains(id(left.element))
            let rightIsFavorite = favorites.contains(id(right.element))
            // Put filled hearts ahead of outlined hearts.
            if leftIsFavorite != rightIsFavorite { return leftIsFavorite }
            // Preserve catalog or manifest order inside each group.
            return left.offset < right.offset
        }.map(\.element)
    }

    // Load the bundled metadata-only community catalog once.
    private func loadCommunityCatalog() -> [CommunityCatalogEntry] {
        // Find and decode only the curated identifiers, credits, and source links.
        guard let url = Bundle.main.url(forResource: "community-catalog", withExtension: "json"),
              let catalog = try? JSONDecoder().decode(CommunityCatalog.self, from: Data(contentsOf: url)) else { return [] }
        // Preserve the quality-first order researched for this instrument.
        return favoriteFirst(catalog.songs, id: { self.communityFavoriteID(for: $0) })
    }

    // Rebuild the picker from protected bundled songs and current local storage.
    private func refreshLibrary(selectingID requestedID: String? = nil) {
        // Reload disk state so favourites and clearing are reflected immediately.
        songs = loadLibrary()
        // Replace every visible title in one deterministic pass.
        songPicker.removeAllItems()
        songPicker.addItems(withTitles: songs.map(pickerTitle))
        // Preserve the requested identity when it still exists after sorting or clearing.
        if let requestedID, let index = songs.firstIndex(where: { $0.id == requestedID }) {
            songPicker.selectItem(at: index)
        } else if !songs.isEmpty {
            // Fall back to protected Aloha at index zero.
            songPicker.selectItem(at: 0)
        }
        // Refresh the subtitle and favourite-button state for the selected row.
        updateSubtitle()
        // Refresh the visible cards even though the legacy picker remains as an internal compatibility helper.
        rebuildLibraryRows()
    }

    // Prefix favourites inside the selector without changing their stored title.
    private func pickerTitle(for song: Song) -> String {
        // Show a filled heart only for persistent local favourites.
        return song.isFavorite ? "♥ \(song.title)" : song.title
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

    // Fill the saved-song picker and connect selection changes.
    private func configureLibraryPicker() {
        // Route selection changes to the subtitle updater.
        songPicker.target = self
        songPicker.action = #selector(selectionChanged)
        // Populate titles and select protected Aloha at first launch.
        refreshLibrary(selectingID: "aloha_oe")
    }

    // Configure all deterministic import controls.
    private func configureImportControls() {
        // Offer every sensible shared key shift.
        transposePicker.addItems(withTitles: (-6...6).map { "\($0 >= 0 ? "+" : "")\($0) semitones" })
        // Default to no shift before a file recommends one.
        transposePicker.selectItem(at: 6)
        // Recompute the selected-track key when the user changes transposition.
        transposePicker.target = self
        transposePicker.action = #selector(refreshImportSummary)
        // Offer Smart first while retaining every legacy chromatic-note policy.
        policyPicker.addItems(withTitles: ["Smart — key-aware", "Strict — skip black keys", "Snap black keys down", "Snap black keys up"])
        // Default every new import to key-aware reduction.
        policyPicker.selectItem(at: 0)
        // Offer conservative near-onset chord windows.
        mergePicker.addItems(withTitles: ["Off", "15 ms", "25 ms", "40 ms"])
        // Use 25 ms because it matches the existing streaming-safe arrangements.
        mergePicker.selectItem(at: 2)
        // Offer the authored timing plus progressively faster performance options.
        speedPicker.addItems(withTitles: [
            "Timing: relaxed 90%",
            "Timing: original 100%",
            "Timing: lively 110%",
            "Timing: fast 125%",
            "Timing: very fast 150%",
            "Timing: rapid 175%",
            "Timing: maximum 200%",
        ])
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
        // Add one clear personal-performance playback action.
        row.addArrangedSubview(NSButton(title: "Play — 5 second focus time", target: self, action: #selector(playSelected)))
        // Add one persistent favourite toggle for imported saved songs.
        row.addArrangedSubview(favoriteButton)
        // Keep destructive library maintenance inside a compact actions menu.
        let actions = NSPopUpButton(frame: .zero, pullsDown: true)
        actions.addItem(withTitle: "•••")
        actions.addItem(withTitle: "Clear Imported Library…")
        actions.item(at: 1)?.target = self
        actions.item(at: 1)?.action = #selector(clearImportedLibrary)
        row.addArrangedSubview(actions)
        // Return the ready row.
        return row
    }

    // Start or stop one personal score from its own fixed trailing card rail.
    @objc private func libraryPrimaryAction(_ sender: NSButton) {
        // Resolve the visible card index against the current favourite-first order.
        guard songs.indices.contains(sender.tag) else { return }
        // Capture the stable song before playback or sorting changes any row index.
        let song = songs[sender.tag]
        // Let the active row stop itself without requiring the persistent footer.
        if activePlaybackID == libraryFavoriteID(for: song) {
            stopPlayback()
            return
        }
        // Preserve local saved timing while bundled scores use the normal current speed.
        let speed = song.playbackSpeed ?? (song.userProvided == true ? 1.00 : selectedSpeed)
        // Stop any generated preview before sending real keyboard input to Genshin.
        previewPlayer.stop(silent: true)
        // Start through the common player with this card's stable shared identity.
        player.play(song, id: libraryFavoriteID(for: song), at: speed)
    }

    // Listen to a personal score locally without requiring Accessibility permission.
    @objc private func libraryListenAction(_ sender: NSButton) {
        // Resolve the visible personal card safely.
        guard songs.indices.contains(sender.tag) else { return }
        let song = songs[sender.tag]
        let id = libraryFavoriteID(for: song)
        // Stop the active generated preview from this same card.
        if activePreviewID == id { previewPlayer.stop(); return }
        // Decode a bundled or locally saved score through the existing safe loader.
        guard let score = loadScoreForListening(song) else {
            statusLabel.stringValue = "Could not load \(song.title) for listening."
            return
        }
        // Stop only keyboard playback before beginning local audio.
        player.stop()
        previewPlayer.play(score: score, title: song.title, id: id, at: song.playbackSpeed ?? 1.0)
    }

    // Toggle one personal card's heart and immediately restore favourite-first order.
    @objc private func toggleLibraryFavorite(_ sender: NSButton) {
        // Resolve the current card before the following sort changes its index.
        guard songs.indices.contains(sender.tag) else { return }
        // Retain the stable manifest song rather than relying on its display title.
        let song = songs[sender.tag]
        let id = libraryFavoriteID(for: song)
        // Read the latest persisted state so consecutive clicks cannot drift from disk.
        let isFavorite = favoriteStore.favoriteIDs().contains(id)
        do {
            // Persist the shared heart for bundled and imported songs alike.
            try favoriteStore.setFavorite(id, isFavorite: !isFavorite)
            // Retain backwards-compatible imported-song metadata for older app versions.
            if song.userProvided == true {
                _ = try userScoreStore.setFavorite(id: song.id, isFavorite: !isFavorite)
            }
            // Re-load the now favourite-first personal order and redraw the visible card stack.
            refreshLibrary(selectingID: song.id)
            // Confirm the local preference update plainly.
            statusLabel.stringValue = isFavorite ? "Removed from favourites." : "Added to favourites."
        } catch {
            // Leave the visible order unchanged when either local persistence write fails.
            statusLabel.stringValue = "Could not update favourite: \(error.localizedDescription)"
        }
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
        // Return the ready row.
        return row
    }

    // Open a native file picker for MIDI or exported Sky Music sheets.
    @objc private func openMidi() {
        // Create one ordinary macOS open panel.
        let panel = NSOpenPanel()
        // Restrict selection to files rather than folders.
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Restrict visible choices to supported MIDI and Sky Music sheet extensions.
        panel.allowedContentTypes = ["mid", "midi", "txt", "json"].compactMap { UTType(filenameExtension: $0) }
        // Load the chosen score only after the sheet closes successfully.
        if panel.runModal() == .OK, let url = panel.url { loadScore(url) }
    }

    // Dispatch a dropped or selected file to its strict supported score reader.
    private func loadScore(_ url: URL) {
        // Route exported Sky Music sheets through their native timed-key converter.
        if ["txt", "json"].contains(url.pathExtension.lowercased()) { loadSkyMusicSheet(url) } else { loadMidi(url) }
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
            // Replace any earlier direct-sheet conversion with this MIDI document.
            directImportedScore = nil
            // Use the source filename as the performance title.
            importedTitle = url.deletingPathExtension().lastPathComponent
            // Preserve the complete filename for the live analysis summary.
            importedFilename = url.lastPathComponent
            // Apply the engine's best shared key recommendation.
            transposePicker.selectItem(at: max(0, min(12, document.bestTranspose + 6)))
            // Begin every newly loaded MIDI with the recommended Smart policy.
            policyPicker.selectItem(at: 0)
            // Rebuild one enabled checkbox per musical source track.
            rebuildTrackButtons(document.tracks)
            // Show selected-track fit and the key Smart will use.
            refreshImportSummary()
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

    // Decode one exported Sky Music JSON/text sheet without copying the source file.
    private func loadSkyMusicSheet(_ url: URL) {
        do {
            // Read and validate the established one-song array wrapper exactly.
            let source = try CommunitySourceSong.decodeResponse(Data(contentsOf: url))
            let score = try source.makeScore()
            // Commit state only after every conversion boundary has passed.
            directImportedScore = score
            importedDocument = nil
            importedTitle = source.name
            importedFilename = url.lastPathComponent
            // Remove MIDI-only track controls because this format is already key-mapped.
            rebuildTrackButtons([])
            tracksStack.addArrangedSubview(makeSecondaryLabel("Sky Music sheet — timing and chords preserved."))
            importSummaryLabel.stringValue = "\(importedFilename) • \(score.count) timed lyre events • ready to preview or save"
            playImportedButton.isEnabled = true
            saveImportedButton.isEnabled = true
            statusLabel.stringValue = "Sky Music sheet imported locally. No source file was copied."
        } catch {
            // Preserve the previous successfully loaded score on a malformed text/JSON file.
            statusLabel.stringValue = "This is not a supported Sky Music exported sheet: \(error.localizedDescription)"
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
            let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(refreshImportSummary))
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

    // Refresh selected-track fit and detected key after import-option changes.
    @objc private func refreshImportSummary() {
        // Explain an already-converted direct Sky Music sheet without MIDI-only analysis.
        if let directImportedScore {
            importSummaryLabel.stringValue = "\(importedFilename) • \(directImportedScore.count) timed lyre events • ready to preview or save"
            return
        }
        // Leave the initial instruction untouched before a MIDI is loaded.
        guard let document = importedDocument else { return }
        // Read the exact source tracks currently enabled in the UI.
        let enabled = Set(trackButtons.compactMap { index, button in button.state == .on ? index : nil })
        // Explain an empty selection directly instead of inventing a key.
        guard !enabled.isEmpty else {
            importSummaryLabel.stringValue = "\(importedFilename) • No musical tracks enabled"
            return
        }
        // Read the visible shared transpose.
        let transpose = transposePicker.indexOfSelectedItem - 6
        // Count only notes belonging to the enabled track checkboxes.
        let selectedTracks = document.tracks.filter { enabled.contains($0.index) }
        let totalNotes = selectedTracks.reduce(0) { $0 + $1.noteCount }
        // Measure directly playable notes under the selected shared shift.
        let fit = document.naturalFit(transpose: transpose, enabledTrackIndexes: enabled)
        // Detect the same key the Smart converter will use for this selection.
        let keyName = document.detectedKey(transpose: transpose, enabledTrackIndexes: enabled)?.name ?? "Unknown"
        // Present honest source and reduction facts in one readable summary.
        importSummaryLabel.stringValue = "\(importedFilename) • \(formatDuration(document.durationMs)) • \(totalNotes) notes • \(selectedTracks.count) enabled tracks • \(String(format: "%.1f", fit * 100))% natural-note fit at \(signed(transpose)) • Detected key: \(keyName)"
    }

    // Convert current controls into one deterministic score.
    private func importedScore() -> [AppScoreEvent]? {
        // Return a direct source conversion before consulting MIDI-only controls.
        if let directImportedScore { return directImportedScore }
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
        // Stop local Listen audio before sending the imported score as keyboard input.
        previewPlayer.stop(silent: true)
        // Play without writing or copying the source MIDI.
        player.play(score: score, title: importedTitle, id: "import:preview", at: selectedSpeed)
    }

    // Save the current generated reduction to the user's local picker library.
    @objc private func saveImported() {
        // Regenerate from the visible options so saved and previewed notes match.
        guard let score = importedScore() else { return }
        // Write generated JSON and refresh the picker.
        do {
            // Persist score events plus the timing selected for this performance.
            let song = try userScoreStore.save(title: importedTitle, events: score, playbackSpeed: selectedSpeed)
            // Reload and select the new stable ID through the common picker path.
            refreshLibrary(selectingID: song.id)
            // Confirm the local-only storage boundary.
            statusLabel.stringValue = "Saved generated score locally at \(formattedSpeed(selectedSpeed)). The original MIDI was not copied."
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
        guard songs.indices.contains(index) else { return }
        // Use a local song's persisted timing; legacy local entries safely default to original speed.
        let speed = songs[index].playbackSpeed ?? (songs[index].userProvided == true ? 1.00 : selectedSpeed)
        // Start playback without allowing the live picker to override persisted local timing.
        player.play(songs[index], id: libraryFavoriteID(for: songs[index]), at: speed)
    }

    // Reflect saved-song selection changes beneath the picker.
    @objc private func selectionChanged() { updateSubtitle() }

    // Toggle the selected imported performance's persistent favourite state.
    @objc private func toggleFavorite() {
        // Resolve the current picker row safely.
        let index = songPicker.indexOfSelectedItem
        // Protect Aloha and reject an absent local selection.
        guard songs.indices.contains(index), songs[index].userProvided == true else { return }
        // Preserve the stable ID across favourite-driven reordering.
        let selected = songs[index]
        do {
            // Persist the inverse state through the local-only score store.
            _ = try userScoreStore.setFavorite(id: selected.id, isFavorite: !selected.isFavorite)
            // Reload titles, order, subtitle, and button label around that same ID.
            refreshLibrary(selectingID: selected.id)
            // Confirm the durable result without changing playback.
            statusLabel.stringValue = selected.isFavorite ? "Removed from favourites." : "Added to favourites."
        } catch {
            // Leave the current picker untouched when persistence fails.
            statusLabel.stringValue = "Could not update favourite: \(error.localizedDescription)"
        }
    }

    // Confirm and remove every locally generated arrangement while preserving Aloha.
    @objc private func clearImportedLibrary() {
        // Explain the exact destructive boundary before any file write.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear imported library?"
        alert.informativeText = "This removes generated saved arrangements. Aloha ʻOe and your original MIDI files remain untouched."
        // Make the destructive and cancellation choices explicit.
        alert.addButton(withTitle: "Clear Imported Songs")
        alert.addButton(withTitle: "Cancel")
        // Perform no writes when the user cancels or closes the alert.
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            // Clear only the dedicated Application Support score store.
            try userScoreStore.clear()
            // Return the live selector to protected Aloha immediately.
            refreshLibrary(selectingID: "aloha_oe")
            // Confirm exactly what survived.
            statusLabel.stringValue = "Imported library cleared. Aloha ʻOe and original MIDI files were kept."
        } catch {
            // Keep the existing in-memory picker when clearing fails.
            statusLabel.stringValue = "Could not clear imported library: \(error.localizedDescription)"
        }
    }

    // Copy the selected saved arrangement subtitle into the window.
    private func updateSubtitle() {
        // Resolve the selected row safely.
        let index = songPicker.indexOfSelectedItem
        // Show a fallback only when the bundle has no manifest.
        guard songs.indices.contains(index) else {
            subtitleLabel.stringValue = "No bundled songs found."
            favoriteButton.isEnabled = false
            return
        }
        // Show the selected arrangement description.
        let selected = songs[index]
        // Explain independent local timing and make legacy 100% fallback visible.
        let timing = selected.userProvided == true ? " · Saved speed: \(formattedSpeed(selected.playbackSpeed ?? 1.00))" : ""
        subtitleLabel.stringValue = selected.subtitle + timing
        // Protect bundled Aloha from local metadata actions.
        favoriteButton.isEnabled = selected.userProvided == true
        // Reflect the selected local entry's persistent state.
        favoriteButton.title = selected.isFavorite ? "♥ Unfavourite" : "♡ Favourite"
    }

    // Stop either bundled or imported playback.
    @objc private func stopPlayback() { player.stop() }

    // Translate the mapping popup into the engine's explicit enum.
    private var selectedMissingPolicy: MissingNotePolicy {
        // Match the configured popup order.
        switch policyPicker.indexOfSelectedItem {
        case 1: return .skip
        case 2: return .down
        case 3: return .up
        default: return .smart
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
        case 3: return 1.25
        case 4: return 1.50
        case 5: return 1.75
        case 6: return 2.00
        default: return 1.00
        }
    }

    // Format one speed multiplier using the same whole-percent language as playback status.
    private func formattedSpeed(_ speed: Double) -> String {
        // Convert a multiplier such as 1.25 into a concise 125% label.
        return "\(Int((speed * 100).rounded()))%"
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
