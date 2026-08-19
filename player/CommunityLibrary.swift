// Import Foundation for Codable source data, URLs, and Application Support caching.
import Foundation

// Describe one metadata-only entry in the curated community collection.
struct CommunityCatalogEntry: Codable, Equatable {
    // Keep a repository-owned stable identity for cache filenames and UI selection.
    let id: String
    // Display the arrangement title exactly as curated.
    let title: String
    // Credit the community arranger when the upstream source identifies one.
    let arranger: String?
    // Show a concise researched duration before downloading note data.
    let durationSeconds: Int?
    // Identify the upstream Sky Music arrangement without bundling its notes.
    let remoteFile: String
    // Link users back to the community source collection.
    let sourceURL: String
    // Keep the original visual sheet page for on-demand JSON export when available.
    var visualSheetURL: String? = nil
    // Preserve the source website category without inventing a genre.
    var category: String? = nil

    // Present honest attribution even when upstream authorship is missing.
    var creditLine: String {
        // Name a known arranger and the collection that supplied the arrangement.
        if let arranger, !arranger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Arranged by \(arranger) · Sky Music community"
        }
        // Never invent an arranger when the old library does not provide one.
        return "Community arrangement · Sky Music library"
    }
}

// Wrap the metadata resource in a future-compatible top-level object.
struct CommunityCatalog: Codable {
    // Preserve the deliberate quality-first catalog order.
    let songs: [CommunityCatalogEntry]
}

// Model one absolute-time source note from the Sky Music API.
struct CommunitySourceNote: Codable {
    // Preserve the source's authored onset in milliseconds.
    let time: Int
    // Preserve the source key identifier until strict validation.
    let key: String
}

// Model the useful fields of one remotely returned community song.
struct CommunitySourceSong: Codable {
    // Retain the upstream title for diagnostics.
    let name: String
    // Retain every authored note onset and simultaneous key.
    let songNotes: [CommunitySourceNote]

    // Decode the endpoint's one-song array wrapper and reject an absent result.
    static func decodeResponse(_ data: Data) throws -> CommunitySourceSong {
        // Decode the exact JSON array returned by the legacy endpoint.
        let songs = try JSONDecoder().decode([CommunitySourceSong].self, from: data)
        // Require one actual source song instead of treating an empty search as music.
        guard let song = songs.first else { throw CommunityLibraryError.emptyResponse }
        // Return only the requested first result.
        return song
    }

    // Convert the source's fifteen sequential natural notes into safe Genshin events.
    func makeScore() throws -> [ImportedScoreEvent] {
        // Require audible content before any cache or playback operation.
        guard !songNotes.isEmpty else { throw CommunityLibraryError.emptyArrangement }
        // Map the old fifteen-key range onto C3 through C5 inside Genshin's 21 keys.
        let destinationKeys = Array("zxcvbnmasdfghjq").map(String.init)
        // Group simultaneous source notes without losing their exact absolute time.
        var grouped: [Int: [Int]] = [:]
        // Validate each untrusted remote note independently.
        for note in songNotes {
            // Negative absolute time would create invalid playback delays.
            guard note.time >= 0 else { throw CommunityLibraryError.negativeTimestamp }
            // Accept exactly the documented `1Key0` through `1Key14` identifiers.
            guard note.key.hasPrefix("1Key"),
                  let index = Int(note.key.dropFirst(4)),
                  destinationKeys.indices.contains(index),
                  note.key == "1Key\(index)" else {
                throw CommunityLibraryError.unknownSourceKey(note.key)
            }
            // Append the validated scale index at its authored onset.
            grouped[note.time, default: []].append(index)
        }
        // Convert absolute onsets into the app's delay-before-event schema.
        var previousTime = 0
        var score: [ImportedScoreEvent] = []
        // Emit source onsets in chronological order regardless of response ordering.
        for time in grouped.keys.sorted() {
            // Keep distinct notes in stable low-to-high order for deterministic chords.
            let indexes = Array(Set(grouped[time] ?? [])).sorted()
            // Preserve the player's established three-key streaming safety limit.
            let keys = indexes.prefix(3).map { destinationKeys[$0] }
            // Every group began with at least one validated source note.
            guard !keys.isEmpty else { continue }
            // Preserve the first lead-in and every later authored interval exactly.
            score.append(ImportedScoreEvent(delayMs: time - previousTime, keys: keys))
            // Advance the absolute-time cursor only after emitting this onset.
            previousTime = time
        }
        // Return only a non-empty safe conversion.
        guard !score.isEmpty else { throw CommunityLibraryError.emptyArrangement }
        return score
    }
}

// Describe failures at the remote-data and cache trust boundaries.
enum CommunityLibraryError: LocalizedError {
    // The endpoint returned no matching song.
    case emptyResponse
    // The source contained no audible notes.
    case emptyArrangement
    // The source contained time before zero.
    case negativeTimestamp
    // The source used a key outside its fifteen-key contract.
    case unknownSourceKey(String)
    // A repository catalog identity could escape the cache directory.
    case unsafeCatalogID

    // Convert each boundary failure into concise UI status text.
    var errorDescription: String? {
        // Explain the precise validation failure without exposing internal paths.
        switch self {
        case .emptyResponse: return "The community library returned no arrangement."
        case .emptyArrangement: return "The community arrangement contains no playable notes."
        case .negativeTimestamp: return "The community arrangement contains invalid timing."
        case .unknownSourceKey(let key): return "The community arrangement uses an unsupported key: \(key)."
        case .unsafeCatalogID: return "The community catalog contains an unsafe song identity."
        }
    }
}

// Retain attribution beside one locally cached converted score.
struct CachedCommunityRecord: Codable, Equatable {
    // Preserve every visible source and credit field.
    let entry: CommunityCatalogEntry
    // Locate the converted score inside the dedicated cache directory.
    let filename: String
}

// Wrap all cached records in a version-tolerant manifest object.
struct CommunityCacheManifest: Codable {
    // Retain stable record order for deterministic UI state.
    let records: [CachedCommunityRecord]
}

// Cache validated converted community scores without copying them into the repository.
final class CommunityScoreStore {
    // Keep all writes beneath one injected or standard Application Support root.
    private let root: URL
    // Separate remote community data from the user's imported MIDI scores.
    private var scoresDirectory: URL { root.appendingPathComponent("Community Scores", isDirectory: true) }
    // Store attribution and cache filenames beside, not inside, score payloads.
    private var manifestURL: URL { root.appendingPathComponent("community-library.json") }

    // Resolve the normal app root while allowing isolated deterministic tests.
    init(root: URL? = nil) {
        // Ask Foundation for the current user's Application Support directory.
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Use an injected root or the stable Teyvat Virtuoso application folder.
        self.root = root ?? applicationSupport.appendingPathComponent("Teyvat Virtuoso", isDirectory: true)
    }

    // Load valid cache records whose converted score files still exist.
    func loadRecords() -> [CachedCommunityRecord] {
        // Treat a missing or malformed manifest as an empty optional cache.
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CommunityCacheManifest.self, from: data) else { return [] }
        // Hide stale records without deleting unrelated files.
        return manifest.records.filter { FileManager.default.fileExists(atPath: scoresDirectory.appendingPathComponent($0.filename).path) }
    }

    // Report whether one curated entry already has a valid local record.
    func isCached(_ entry: CommunityCatalogEntry) -> Bool {
        // Match only the stable repository-owned catalog identity.
        return loadRecords().contains(where: { $0.entry.id == entry.id })
    }

    // Decode one locally cached converted score when available.
    func cachedScore(for entry: CommunityCatalogEntry) -> [ImportedScoreEvent]? {
        // Resolve the manifest-owned filename for this catalog entry.
        guard let record = loadRecords().first(where: { $0.entry.id == entry.id }) else { return nil }
        // Require readable JSON matching the established score schema.
        guard let data = try? Data(contentsOf: scoresDirectory.appendingPathComponent(record.filename)),
              let score = try? JSONDecoder().decode([ImportedScoreEvent].self, from: data),
              !score.isEmpty else { return nil }
        // Return only score data produced by the validated converter.
        return score
    }

    // Remove one locally cached conversion without touching remote source data or metadata catalogue rows.
    func remove(entry: CommunityCatalogEntry) throws {
        // Resolve only a manifest-owned record for this stable catalogue identity.
        guard let record = loadRecords().first(where: { $0.entry.id == entry.id }) else { return }
        // Build the expected local cache path from the manifest-owned safe filename.
        let scoreURL = scoresDirectory.appendingPathComponent(record.filename)
        // Delete only that converted local score when it still exists.
        if FileManager.default.fileExists(atPath: scoreURL.path) { try FileManager.default.removeItem(at: scoreURL) }
        // Remove only this record while preserving every other cached arrangement.
        let remaining = loadRecords().filter { $0.entry.id != entry.id }
        // Keep the manifest valid even after removing its final cached record.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(CommunityCacheManifest(records: remaining)).write(to: manifestURL, options: .atomic)
    }

    // Persist one validated conversion and its complete attribution atomically.
    func cache(entry: CommunityCatalogEntry, score: [ImportedScoreEvent]) throws {
        // Restrict cache filenames to a conservative repository-owned identity alphabet.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !entry.id.isEmpty,
              entry.id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw CommunityLibraryError.unsafeCatalogID
        }
        // Refuse empty generated data even when a caller bypasses source conversion.
        guard !score.isEmpty else { throw CommunityLibraryError.emptyArrangement }
        // Create only the precise app and community score directories.
        try FileManager.default.createDirectory(at: scoresDirectory, withIntermediateDirectories: true)
        // Derive a deterministic safe filename from the validated catalog identity.
        let filename = "\(entry.id).json"
        // Keep cached score JSON readable for local recovery and inspection.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Write converted keys rather than the original copyrighted source payload.
        try encoder.encode(score).write(to: scoresDirectory.appendingPathComponent(filename), options: .atomic)
        // Replace any older record for the same curated identity.
        let record = CachedCommunityRecord(entry: entry, filename: filename)
        let records = loadRecords().filter { $0.entry.id != entry.id } + [record]
        // Ensure the root exists before atomically replacing its manifest.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(CommunityCacheManifest(records: records)).write(to: manifestURL, options: .atomic)
    }
}
