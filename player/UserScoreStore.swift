// Import Foundation for Codable models and Application Support persistence.
import Foundation

// Model one bundled or locally generated performance picker entry.
struct Song: Codable, Equatable {
    // Keep a stable picker identity across sorting and app restarts.
    let id: String
    // Display the human-friendly performance title.
    let title: String
    // Display a concise arrangement description.
    let subtitle: String
    // Locate the matching generated or bundled JSON score.
    let file: String
    // Mark generated Application Support scores without changing public manifests.
    let userProvided: Bool?
    // Persist whether a local performance belongs at the top of the personal library.
    let isFavorite: Bool

    // Keep programmatic creation concise while defaulting old and new entries safely.
    init(id: String, title: String, subtitle: String, file: String, userProvided: Bool? = nil, isFavorite: Bool = false) {
        // Store the stable identity.
        self.id = id
        // Store the visible title.
        self.title = title
        // Store the visible description.
        self.subtitle = subtitle
        // Store the score filename.
        self.file = file
        // Store whether the file lives under Application Support.
        self.userProvided = userProvided
        // Store the explicit favourite state.
        self.isFavorite = isFavorite
    }

    // Name every persisted field for backward-compatible custom decoding.
    private enum CodingKeys: String, CodingKey {
        // Preserve the existing manifest field names.
        case id, title, subtitle, file, userProvided, isFavorite
    }

    // Decode manifests written before favourites existed.
    init(from decoder: Decoder) throws {
        // Open the keyed song object.
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Decode every previously required string exactly.
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        subtitle = try values.decode(String.self, forKey: .subtitle)
        file = try values.decode(String.self, forKey: .file)
        // Preserve the optional local-source marker when present.
        userProvided = try values.decodeIfPresent(Bool.self, forKey: .userProvided)
        // Treat a missing legacy favourite field as false.
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

// Model the small JSON wrapper around all available local songs.
struct SongLibrary: Codable {
    // Preserve the curated or user-sorted picker order.
    let songs: [Song]
}

// Describe local-library operations that cannot be completed safely.
enum UserScoreStoreError: LocalizedError {
    // Reject a stale or foreign song identity.
    case songNotFound

    // Convert store failures into one concise status-line explanation.
    var errorDescription: String? {
        // Explain the only domain-specific mutation failure.
        return "The selected imported song was not found."
    }
}

// Persist generated JSON scores without ever copying their original private MIDI source.
final class UserScoreStore {
    // Keep generated data under the standard per-user Application Support location.
    private let root: URL
    // Store generated event JSON files in one dedicated child folder.
    private var scoresDirectory: URL { root.appendingPathComponent("Scores", isDirectory: true) }
    // Store user picker entries in one small local manifest.
    private var manifestURL: URL { root.appendingPathComponent("custom-library.json") }

    // Resolve the normal app-support root while allowing deterministic test injection.
    init(root: URL? = nil) {
        // Ask Foundation for the current user's Application Support directory.
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Use an injected root or the stable Teyvat Virtuoso folder.
        self.root = root ?? applicationSupport.appendingPathComponent("Teyvat Virtuoso", isDirectory: true)
    }

    // Load valid locally generated picker entries with favourites first.
    func loadSongs() -> [Song] {
        // Treat a missing or malformed manifest as an empty local library.
        guard let data = try? Data(contentsOf: manifestURL),
              let library = try? JSONDecoder().decode(SongLibrary.self, from: data) else { return [] }
        // Hide entries whose generated score file no longer exists.
        let valid = library.songs.filter { FileManager.default.fileExists(atPath: scoreURL(for: $0.file).path) }
        // Retain stable order inside the favourite and ordinary groups.
        return sorted(valid)
    }

    // Resolve one generated score filename without accepting path traversal.
    func scoreURL(for filename: String) -> URL {
        // Strip supplied directory components and retain only the last filename.
        return scoresDirectory.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent)
    }

    // Save one generated reduction and append it to the local picker manifest.
    func save(title: String, events: [ImportedScoreEvent]) throws -> Song {
        // Create the precise application and score folders when first needed.
        try FileManager.default.createDirectory(at: scoresDirectory, withIntermediateDirectories: true)
        // Use a unique filename so repeated saves never overwrite an earlier arrangement.
        let filename = "\(UUID().uuidString.lowercased()).json"
        // Create the user-visible local picker entry outside the favourites group.
        let song = Song(
            id: "local-\(UUID().uuidString.lowercased())",
            title: title,
            subtitle: "Imported MIDI · locally generated lyre score",
            file: filename,
            userProvided: true,
            isFavorite: false
        )
        // Encode readable JSON compatible with the bundled score schema.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Write the generated key events atomically.
        try encoder.encode(events).write(to: scoreURL(for: filename), options: .atomic)
        // Preserve existing valid local entries and append the new one.
        try writeManifest(loadSongs() + [song])
        // Return the new entry for immediate picker selection.
        return song
    }

    // Persist one local song's favourite state and return the newly sorted library.
    func setFavorite(id: String, isFavorite: Bool) throws -> [Song] {
        // Read only valid current local entries.
        let current = loadSongs()
        // Reject stale IDs before writing a changed manifest.
        guard current.contains(where: { $0.id == id }) else { throw UserScoreStoreError.songNotFound }
        // Rebuild the immutable matching entry with its requested favourite state.
        let updated = current.map { song in
            // Preserve every unrelated local entry exactly.
            guard song.id == id else { return song }
            // Copy all stable metadata while changing only the favourite flag.
            return Song(id: song.id, title: song.title, subtitle: song.subtitle, file: song.file, userProvided: song.userProvided, isFavorite: isFavorite)
        }
        // Sort and persist the complete valid local library atomically.
        let ordered = sorted(updated)
        try writeManifest(ordered)
        // Return the order the picker should display immediately.
        return ordered
    }

    // Remove every generated arrangement while staying inside this store's root.
    func clear() throws {
        // Remove only the dedicated generated-score directory when it exists.
        if FileManager.default.fileExists(atPath: scoresDirectory.path) {
            try FileManager.default.removeItem(at: scoresDirectory)
        }
        // Recreate the precise empty directory for the next import save.
        try FileManager.default.createDirectory(at: scoresDirectory, withIntermediateDirectories: true)
        // Replace the active manifest with an empty library atomically.
        try writeManifest([])
    }

    // Write one complete local manifest after its score files are ready.
    private func writeManifest(_ songs: [Song]) throws {
        // Ensure the app root exists before its first manifest write.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Keep manifests readable and deterministic for recovery.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Replace the manifest atomically so a crash cannot leave partial JSON.
        try encoder.encode(SongLibrary(songs: songs)).write(to: manifestURL, options: .atomic)
    }

    // Group favourites first while retaining stable order within each group.
    private func sorted(_ songs: [Song]) -> [Song] {
        // Attach source positions because Swift sorting does not promise stability.
        return songs.enumerated().sorted { left, right in
            // Put favourite entries before ordinary entries.
            if left.element.isFavorite != right.element.isFavorite {
                return left.element.isFavorite && !right.element.isFavorite
            }
            // Preserve the existing manifest order for equal favourite state.
            return left.offset < right.offset
        }.map(\.element)
    }
}
