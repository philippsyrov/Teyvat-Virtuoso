// Import Foundation for Codable manifests and Application Support storage.
import Foundation

// Wrap all persistent favourite identities in one forward-compatible JSON object.
private struct FavoriteManifest: Codable {
    // Preserve every stable score identity that belongs at the top of its page.
    let ids: [String]
}

// Describe the one invalid write the app can reject before touching disk.
enum FavoriteStoreError: LocalizedError {
    // Reject an empty identity because it cannot identify a score safely.
    case emptyID

    // Turn the domain failure into a concise status-line explanation.
    var errorDescription: String? {
        // Explain the rejected data without leaking any filesystem detail.
        return "This score could not be added to favourites."
    }
}

// Persist favourite identities for bundled, imported, and community score cards.
final class FavoriteStore {
    // Keep all writes under one injected or normal application-support root.
    private let root: URL
    // Store only identifiers rather than any score, MIDI, or remote note content.
    private var manifestURL: URL { root.appendingPathComponent("favorites.json") }

    // Resolve the normal app root while allowing deterministic test injection.
    init(root: URL? = nil) {
        // Ask Foundation for the current user's Application Support directory.
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Use the supplied test root or the standard Teyvat Virtuoso folder.
        self.root = root ?? applicationSupport.appendingPathComponent("Teyvat Virtuoso", isDirectory: true)
    }

    // Return every persisted favourite identity as a set for cheap card lookups.
    func favoriteIDs() -> Set<String> {
        // Treat an absent or malformed manifest as an empty favourite list.
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(FavoriteManifest.self, from: data) else { return [] }
        // De-duplicate any manually edited manifest while reading it safely.
        return Set(manifest.ids)
    }

    // Persist one explicit favourite state without changing unrelated identities.
    func setFavorite(_ id: String, isFavorite: Bool) throws {
        // Refuse whitespace-only identities before any manifest mutation.
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw FavoriteStoreError.emptyID }
        // Start from the current on-disk state rather than stale UI state.
        var ids = favoriteIDs()
        // Insert the identity for a filled heart.
        if isFavorite {
            ids.insert(normalizedID)
        } else {
            // Remove the identity for an outlined heart.
            ids.remove(normalizedID)
        }
        // Ensure the exact parent exists before its first atomic write.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Keep the small manifest readable and deterministic for recovery.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Replace the complete list atomically so a crash cannot leave partial JSON.
        try encoder.encode(FavoriteManifest(ids: ids.sorted())).write(to: manifestURL, options: .atomic)
    }
}
