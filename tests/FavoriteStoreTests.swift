// Import Foundation for isolated temporary folders and process termination.
import Foundation

// Fail immediately with one readable persistence-contract error.
func favoriteExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Evaluate each assertion once before continuing.
    guard condition() else {
        // Print the precise failed expectation for the Python wrapper.
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        // Exit nonzero so test failures cannot look successful.
        exit(1)
    }
}

// Exercise the shared favourite store against a real isolated filesystem root.
@main
struct FavoriteStoreTests {
    // Run every favourite persistence contract in one executable.
    static func main() throws {
        // Give this test a unique parent that cannot overlap real user storage.
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Use the same final folder name as production Application Support storage.
        let root = parent.appendingPathComponent("Teyvat Virtuoso", isDirectory: true)
        // Remove only this test's unique parent after it finishes.
        defer { try? FileManager.default.removeItem(at: parent) }

        // Load the production store against the isolated root.
        let store = FavoriteStore(root: root)
        // Begin with no favourite identities.
        favoriteExpect(store.favoriteIDs().isEmpty, "expected an empty fresh favourite store")
        // Persist two different card namespaces.
        try store.setFavorite("community:illusionary-daytime", isFavorite: true)
        try store.setFavorite("library:aloha_oe", isFavorite: true)
        // Confirm a fresh store instance retains both identities.
        favoriteExpect(Array(FavoriteStore(root: root).favoriteIDs()).sorted() == ["community:illusionary-daytime", "library:aloha_oe"], "expected favourites to survive restart in sorted order")
        // Remove one identity without disturbing the other.
        try store.setFavorite("community:illusionary-daytime", isFavorite: false)
        favoriteExpect(Array(FavoriteStore(root: root).favoriteIDs()).sorted() == ["library:aloha_oe"], "expected removing one favourite to preserve the other")

        // Report the exact success marker expected by the Python wrapper.
        print("FavoriteStoreTests passed")
    }
}
