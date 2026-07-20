// Import Foundation for temporary folders, JSON fixtures, and process termination.
import Foundation

// Fail immediately with a precise persistence-contract message.
func storeExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Evaluate each assertion exactly once.
    guard condition() else {
        // Print the readable failure for the Python wrapper and local terminal.
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        // Exit nonzero so verification cannot silently continue.
        exit(1)
    }
}

// Exercise the personal-library store against an isolated real filesystem root.
@main
struct UserScoreStoreTests {
    // Run every persistence contract from one dependency-free executable.
    static func main() throws {
        // Give this run a unique parent folder so clear tests cannot touch user data.
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Put the injected app root under that isolated parent.
        let root = parent.appendingPathComponent("Teyvat Virtuoso", isDirectory: true)
        // Create the legacy score directory before writing its fixture.
        let scores = root.appendingPathComponent("Scores", isDirectory: true)
        try FileManager.default.createDirectory(at: scores, withIntermediateDirectories: true)
        // Clean the unique temporary parent after every successful or failed throw unwind.
        defer { try? FileManager.default.removeItem(at: parent) }

        // Write one generated score referenced by an old manifest without isFavorite.
        try Data("[{\"delayMs\":0,\"keys\":[\"a\"]}]".utf8).write(to: scores.appendingPathComponent("legacy.json"))
        // Preserve the exact pre-favourites JSON shape for backward-compatibility coverage.
        let legacyManifest = """
        {"songs":[{"id":"legacy","title":"Legacy","subtitle":"Old import","file":"legacy.json","userProvided":true}]}
        """
        // Write the old local manifest at the production filename.
        try Data(legacyManifest.utf8).write(to: root.appendingPathComponent("custom-library.json"))

        // Load the real store against only the injected root.
        let store = UserScoreStore(root: root)
        // Decode missing favourite metadata as false instead of rejecting old libraries.
        storeExpect(store.loadSongs().first?.isFavorite == false, "expected old manifests to decode as non-favourite")

        // Save a new generated arrangement using the production event schema.
        let saved = try store.save(title: "Pirates", events: [ImportedScoreEvent(delayMs: 0, keys: ["a"])])
        // Start every newly imported song outside the favourites group.
        storeExpect(saved.isFavorite == false, "expected new songs to start non-favourite")
        // Persist a favourite toggle and receive the newly sorted local library.
        let reordered = try store.setFavorite(id: saved.id, isFavorite: true)
        // Put the favourite first without changing its stable identity.
        storeExpect(reordered.first?.id == saved.id && reordered.first?.isFavorite == true, "expected persistent favourite sorting")
        // Confirm a fresh store instance sees the same persisted favourite state.
        storeExpect(UserScoreStore(root: root).loadSongs().first?.id == saved.id, "expected favourite order to survive restart")

        // Reject attempts to mutate an ID that does not belong to the local manifest.
        do {
            // Exercise the exact unknown-ID boundary.
            _ = try store.setFavorite(id: "missing", isFavorite: true)
            // Fail if the store silently accepts the unknown ID.
            storeExpect(false, "expected unknown favourite ID to fail")
        } catch {
            // Require a readable message rather than a generic Cocoa failure.
            storeExpect(error.localizedDescription.contains("not found"), "expected readable unknown-ID error")
        }

        // Place an unrelated sibling outside the injected app root.
        let sibling = parent.appendingPathComponent("outside.txt")
        // Give it content so existence proves the clear boundary.
        try Data("keep".utf8).write(to: sibling)
        // Clear only generated arrangements through the production method.
        try store.clear()
        // Return the local manifest to an empty library.
        storeExpect(store.loadSongs().isEmpty, "expected cleared imported library")
        // Preserve every file outside the injected Teyvat Virtuoso root.
        storeExpect(FileManager.default.fileExists(atPath: sibling.path), "expected clear to stay inside store root")

        // Confirm success for the surrounding Python harness.
        print("UserScoreStoreTests passed")
    }
}
