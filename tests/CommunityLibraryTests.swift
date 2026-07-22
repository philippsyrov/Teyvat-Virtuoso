// Import Foundation for deterministic JSON fixtures and temporary storage.
import Foundation

// Keep test failures concise while allowing every contract to run in one executable.
func expectCommunity(_ condition: @autoclosure () -> Bool, _ message: String) {
    // Exit at the first broken community-library contract.
    if !condition() {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

// Exercise the community arrangement boundary without network or AppKit.
@main
struct CommunityLibraryTests {
    // Run conversion, validation, attribution, and cache contracts.
    static func main() throws {
        // Model one valid remote response with a lead-in, a chord, and the highest source key.
        let validJSON = """
        [{"name":"Fixture","songNotes":[
          {"time":100,"key":"1Key0"},
          {"time":350,"key":"1Key2"},
          {"time":350,"key":"1Key4"},
          {"time":700,"key":"1Key14"}
        ]}]
        """.data(using: .utf8)!
        // Decode the exact array wrapper returned by the Sky Music endpoint.
        let source = try CommunitySourceSong.decodeResponse(validJSON)
        // Convert its fifteen sequential natural notes into the safe Genshin subset.
        let score = try source.makeScore()
        // Preserve the authored lead-in instead of starting immediately.
        expectCommunity(score[0] == ImportedScoreEvent(delayMs: 100, keys: ["z"]), "expected low source key and lead-in")
        // Preserve simultaneous notes as one true chord.
        expectCommunity(score[1] == ImportedScoreEvent(delayMs: 250, keys: ["c", "b"]), "expected simultaneous source chord")
        // Fit the fifteenth source key inside the three-row Genshin range.
        expectCommunity(score[2] == ImportedScoreEvent(delayMs: 350, keys: ["q"]), "expected highest source key")

        // Reject every malformed remote condition before writing a cache.
        for invalid in [
            "[{\"name\":\"Empty\",\"songNotes\":[]}]",
            "[{\"name\":\"Negative\",\"songNotes\":[{\"time\":-1,\"key\":\"1Key0\"}]}]",
            "[{\"name\":\"Unknown\",\"songNotes\":[{\"time\":0,\"key\":\"1Key15\"}]}]",
        ] {
            // Decode the structural response first so conversion owns semantic validation.
            let malformed = try CommunitySourceSong.decodeResponse(invalid.data(using: .utf8)!)
            // Require conversion to throw for the malformed musical data.
            do {
                _ = try malformed.makeScore()
                expectCommunity(false, "expected malformed community score rejection")
            } catch {
                // Any typed community validation error satisfies this boundary.
            }
        }

        // Describe one catalog entry with complete visible attribution.
        let entry = CommunityCatalogEntry(
            id: "fixture-song",
            title: "Fixture Song",
            arranger: "Fixture Arranger",
            durationSeconds: 42,
            remoteFile: "Fixture Song.txt",
            sourceURL: "https://example.com/source"
        )
        // Keep a missing arranger honest rather than inventing authorship.
        let anonymous = CommunityCatalogEntry(
            id: "anonymous-song",
            title: "Anonymous Song",
            arranger: nil,
            durationSeconds: 20,
            remoteFile: "Anonymous.txt",
            sourceURL: "https://example.com/anonymous"
        )
        expectCommunity(entry.creditLine == "Arranged by Fixture Arranger · Sky Music community", "expected named credit")
        expectCommunity(anonymous.creditLine == "Community arrangement · Sky Music library", "expected anonymous credit")

        // Isolate cache writes from the real Application Support library.
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let store = CommunityScoreStore(root: temporaryRoot)
        // Persist only converted safe events plus the catalog attribution.
        try store.cache(entry: entry, score: score)
        expectCommunity(store.cachedScore(for: entry) == score, "expected cached converted score")
        expectCommunity(store.loadRecords().first?.entry == entry, "expected cached attribution metadata")
        // Remove only the locally cached conversion while retaining no stale manifest record.
        try store.remove(entry: entry)
        expectCommunity(store.cachedScore(for: entry) == nil, "expected removed cached score")
        expectCommunity(store.loadRecords().isEmpty, "expected removed cache manifest record")
        // Refuse catalog identities that could escape the dedicated cache directory.
        let unsafe = CommunityCatalogEntry(id: "../escape", title: "Unsafe", arranger: nil, durationSeconds: 1, remoteFile: "Unsafe.txt", sourceURL: "https://example.com")
        do {
            try store.cache(entry: unsafe, score: score)
            expectCommunity(false, "expected unsafe catalog identity rejection")
        } catch {
            // The path-safety rejection is the expected result.
        }
        // Confirm success for the surrounding Python harness.
        print("CommunityLibraryTests passed")
    }
}
