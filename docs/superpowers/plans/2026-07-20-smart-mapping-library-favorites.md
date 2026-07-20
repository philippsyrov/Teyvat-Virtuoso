# Smart Mapping and Personal Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic key-aware chromatic-note mapping, persistent favourites, an Aloha-only bundled library, and safe imported-library clearing.

**Architecture:** `MidiEngine.swift` will own musical-key detection and contextual pitch reduction. A new `UserScoreStore.swift` will isolate local library models and persistence from the AppKit window. `GenshinLyrePlayerApp.swift` will present the new controls and refresh the picker from those two sources without changing keyboard playback.

**Tech Stack:** Swift 6 command-line compilation, AppKit, Foundation, CoreGraphics, Python `unittest`, JSON fixtures, ad-hoc macOS bundle signing.

## Global Constraints

- Keep macOS 13 as the minimum supported version.
- Keep the bundle identifier `com.philippsyrov.teyvat-virtuoso` and existing complete-bundle signing.
- Do not modify the Aloha score, keyboard sender, source timing, three-key chord cap, or private MIDI files.
- Smart mapping applies only while converting an imported MIDI; saved JSON scores are never rewritten.
- Keep Strict, Down, and Up policies byte-for-byte compatible with their current output.
- Aloha is protected and remains the first picker entry.
- Every non-obvious musical conversion and persistence boundary receives an explanatory comment.

---

### Task 1: Key detection and Smart chromatic mapping

**Files:**
- Modify: `player/MidiEngine.swift:62-82,335-430`
- Modify: `tests/MidiEngineTests.swift:90-180`

**Interfaces:**
- Consumes: `MidiDocument.notes`, `MidiImportOptions.enabledTrackIndexes`, `MidiImportOptions.transpose`, and the existing natural-note lyre mapping.
- Produces: `MissingNotePolicy.smart`, `MusicalKey`, `MidiDocument.detectedKey(transpose:enabledTrackIndexes:) -> MusicalKey?`, and Smart-aware `MidiDocument.makeScore(options:)`.

- [ ] **Step 1: Write failing engine tests**

Add fixtures to `tests/MidiEngineTests.swift` that assert:

```swift
let dMajorDocument = MidiDocument(
    tracks: [MidiTrackInfo(index: 0, name: "D major", noteCount: 8, minimumNote: 61, maximumNote: 69, chordOnsets: 0)],
    durationMs: 500,
    bestTranspose: 0,
    ticksPerQuarter: 480,
    notes: [62, 66, 69, 62, 64, 66, 69, 61].enumerated().map {
        MidiNoteOn(trackIndex: 0, tick: $0.offset * 60, note: $0.element)
    },
    tempos: [MidiTempoChange(tick: 0, microsecondsPerQuarter: 500_000)]
)
expect(dMajorDocument.detectedKey(transpose: 0, enabledTrackIndexes: [0])?.name == "D major", "expected D-major detection")

let smartCSharp = dMajorDocument.makeScore(options: MidiImportOptions(
    enabledTrackIndexes: [0], transpose: 0, missingNotePolicy: .smart, mergeToleranceMs: 0
))
expect(smartCSharp.contains { $0.keys == ["s"] }, "expected D-major C-sharp to resolve upward to D")
```

Add a C-minor fixture using repeated MIDI pitches `[60, 63, 67, 60, 62, 63, 67, 58]`; assert detection returns `C minor` and Smart maps E-flat downward to D because D belongs to C natural minor while E does not. Add a C-major contour fixture whose same-track sequence begins C-sharp then D-sharp: the first tie resolves C-sharp downward to C, then contour preservation resolves D-sharp downward to D. Add a no-notes key-detection assertion returning `nil`, and retain the existing regression assertions showing `.skip`, `.down`, and `.up` map C-sharp to nil, C, and D respectively.

- [ ] **Step 2: Run the engine contract and verify RED**

Run:

```zsh
swiftc player/MidiEngine.swift tests/MidiEngineTests.swift -o /private/tmp/teyvat-midi-tests
/private/tmp/teyvat-midi-tests
```

Expected: compilation fails because `MissingNotePolicy.smart`, `MusicalKey`, and `detectedKey` do not exist.

- [ ] **Step 3: Implement deterministic key detection**

Add these public engine types and method:

```swift
enum MusicalMode: String {
    case major
    case minor
}

struct MusicalKey: Equatable {
    let tonic: Int
    let mode: MusicalMode
    var name: String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return "\(names[tonic]) \(mode.rawValue)"
    }
    var pitchClasses: Set<Int> {
        let intervals = mode == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        return Set(intervals.map { positiveModulo(tonic + $0, 12) })
    }
}
```

Use the Krumhansl major profile `[6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]` and minor profile `[6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]`. Build the selected, transposed 12-bin note-count histogram; score C major through B major followed by C minor through B minor; retain the first candidate on exact ties.

- [ ] **Step 4: Implement contextual Smart mapping**

Add `.smart` to `MissingNotePolicy`. Replace the one-note-only Smart path with a helper that accepts the detected key plus the previous source and mapped pitches from the same track:

```swift
private func resolvedPitch(
    _ sourcePitch: Int,
    policy: MissingNotePolicy,
    key: MusicalKey?,
    previousSourcePitch: Int?,
    previousMappedPitch: Int?
) -> Int?
```

For Smart chromatic notes, compare `sourcePitch - 1` and `sourcePitch + 1`. Rank each candidate by: scale membership first; then absolute error between the original incoming interval and mapped incoming interval; then lower pitch. Track previous values independently in dictionaries keyed by `trackIndex`. Pass the resolved pitch into a natural-only `lyreKey(forResolvedPitch:)` so legacy modes keep their exact behavior.

- [ ] **Step 5: Run the engine contract and verify GREEN**

Run the same Swift command. Expected final line: `MidiEngineTests passed`.

- [ ] **Step 6: Commit the engine slice**

```zsh
git add player/MidiEngine.swift tests/MidiEngineTests.swift
git commit -m "feat: add key-aware MIDI reduction"
```

---

### Task 2: Isolate and test the personal-library store

**Files:**
- Create: `player/UserScoreStore.swift`
- Create: `tests/UserScoreStoreTests.swift`
- Modify: `player/GenshinLyrePlayerApp.swift:10-111`
- Modify: `scripts/build_app.sh:13`
- Modify: `tests/test_play_score.py:108-125`

**Interfaces:**
- Consumes: `ImportedScoreEvent` from `MidiEngine.swift` and the existing Application Support root.
- Produces: `Song`, `SongLibrary`, `UserScoreStore.loadSongs()`, `save(title:events:)`, `setFavorite(id:isFavorite:)`, `clear()`, and `scoreURL(for:)`.

- [ ] **Step 1: Write failing persistence tests**

Create `tests/UserScoreStoreTests.swift` with a temporary injected root. Test that an old manifest without `isFavorite` decodes as false; `save` creates a non-favourite song; `setFavorite` persists true and returns favourites before ordinary imports; unknown IDs throw a readable store error; and `clear` removes generated score files while leaving an unrelated sibling file outside the injected root untouched.

Use exact assertions such as:

```swift
let saved = try store.save(title: "Pirates", events: [ImportedScoreEvent(delayMs: 0, keys: ["a"])])
expect(saved.isFavorite == false, "expected new songs to start ordinary")
let reordered = try store.setFavorite(id: saved.id, isFavorite: true)
expect(reordered.first?.id == saved.id && reordered.first?.isFavorite == true, "expected persistent favourite sorting")
try store.clear()
expect(store.loadSongs().isEmpty, "expected cleared imported library")
expect(FileManager.default.fileExists(atPath: sibling.path), "expected clear to stay inside store root")
```

- [ ] **Step 2: Run the store test and verify RED**

```zsh
swiftc player/MidiEngine.swift player/UserScoreStore.swift tests/UserScoreStoreTests.swift -o /private/tmp/teyvat-store-tests
```

Expected: failure because `player/UserScoreStore.swift` does not exist.

- [ ] **Step 3: Extract and extend the store**

Move `Song`, `SongLibrary`, and `UserScoreStore` out of the AppKit file. Define `isFavorite` as a non-optional `Bool` with custom `Codable` decoding via `decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false`. Keep `userProvided` backward-compatible in the same decoder. Implement atomic manifest writes through one private `writeManifest(_:)` method.

Implement:

```swift
func setFavorite(id: String, isFavorite: Bool) throws -> [Song]
func clear() throws
```

`setFavorite` rewrites only the matching local entry and sorts favourites first while retaining stable relative order. `clear` removes only `scoresDirectory`, recreates it, and atomically writes `SongLibrary(songs: [])` to the manifest.

- [ ] **Step 4: Wire the new source file into builds and tests**

Update `scripts/build_app.sh` to compile `MidiEngine.swift`, `UserScoreStore.swift`, and `GenshinLyrePlayerApp.swift`. Extend `tests/test_play_score.py` to compile/run `UserScoreStoreTests.swift` and to assert the AppKit file no longer defines `final class UserScoreStore`.

- [ ] **Step 5: Run persistence tests and verify GREEN**

```zsh
swiftc player/MidiEngine.swift player/UserScoreStore.swift tests/UserScoreStoreTests.swift -o /private/tmp/teyvat-store-tests
/private/tmp/teyvat-store-tests
python3 -m unittest tests/test_play_score.py
```

Expected: store contract ends with `UserScoreStoreTests passed`; Python suite is green.

- [ ] **Step 6: Commit the persistence slice**

```zsh
git add player/UserScoreStore.swift player/GenshinLyrePlayerApp.swift scripts/build_app.sh tests/UserScoreStoreTests.swift tests/test_play_score.py
git commit -m "feat: add persistent performance favourites"
```

---

### Task 3: Add Smart and library controls to AppKit

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift:370-810`
- Modify: `scores/public-domain/library.json`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `MissingNotePolicy.smart`, `MidiDocument.detectedKey`, and the extended `UserScoreStore`.
- Produces: Smart-default import controls, detected-key summary, favourite toggling, and confirmation-backed imported-library clearing.

- [ ] **Step 1: Write failing app-contract tests**

Add Python assertions requiring the source to contain `Smart — key-aware`, `toggleFavorite`, `Clear Imported Library…`, `NSAlert`, `userScoreStore.clear()`, and `detectedKey`. Change the manifest assertion to require exactly `['aloha_oe']`. Assert that `aloha_oe_full_2m24s_lyre.json` contains exactly 506 events and has SHA-256 `8226314106d2914858017c4d8cae44e977af6ef6c54e54962f6d1ddd111e7117`.

- [ ] **Step 2: Run Python tests and verify RED**

```zsh
python3 -m unittest tests/test_play_score.py
```

Expected: failures for the missing Smart control, favourite/clear actions, and extra bundled manifest entries.

- [ ] **Step 3: Implement picker refresh and favourites**

Add a retained `favoriteButton`. Replace direct picker mutations with:

```swift
private func refreshLibrary(selectingID: String? = nil)
private func pickerTitle(for song: Song) -> String
@objc private func toggleFavorite()
```

`refreshLibrary` loads bundled Aloha followed by favourite and ordinary local songs, rebuilds titles using `♥ ` only for favourites, preserves the requested ID when possible, and calls `updateSubtitle`. Disable the favourite button for Aloha and label it `♡ Favourite` or `♥ Unfavourite` for local selection.

- [ ] **Step 4: Implement confirmed clearing**

Add `Clear Imported Library…` to the saved-buttons row. `clearImportedLibrary` creates an `NSAlert` whose informative text says original MIDI files and Aloha are retained, adds `Clear Imported Songs` and `Cancel`, and calls `userScoreStore.clear()` only when the destructive button is chosen. On success call `refreshLibrary(selectingID: "aloha_oe")`; on failure show the error in `statusLabel` without changing the picker.

- [ ] **Step 5: Make Smart the import default and expose the detected key**

Configure the policy titles as `['Smart — key-aware', 'Strict — skip black keys', 'Snap black keys down', 'Snap black keys up']` with index zero selected. Update `selectedMissingPolicy` indexes accordingly. Give transpose and track checkboxes actions that call `refreshImportSummary`; that method recomputes enabled tracks, fit, and `document.detectedKey(...)` and includes `Detected key: <name>`.

- [ ] **Step 6: Keep only Aloha in the bundled selector**

Edit `scores/public-domain/library.json` to contain only the existing Aloha entry. Leave redistributable score JSON files in the repository as examples, but do not expose them in the app picker.

- [ ] **Step 7: Run app tests and build**

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
git diff --check
```

Expected: all tests pass, the native bundle builds, and formatting is clean.

- [ ] **Step 8: Commit the AppKit slice**

```zsh
git add player/GenshinLyrePlayerApp.swift scores/public-domain/library.json tests/test_play_score.py
git commit -m "feat: add personal library controls"
```

---

### Task 4: Documentation, migration, installation, and live verification

**Files:**
- Modify: `README.md`
- Modify: `docs/PRIVATE_SCORES.md`
- Generated: `build/Teyvat Virtuoso.app`
- Replace: `/Users/philippsyrov/Desktop/Teyvat Virtuoso.app`
- Move once: `/Users/philippsyrov/Library/Application Support/Teyvat Virtuoso` to `/Users/philippsyrov/Library/Application Support/Teyvat Virtuoso Backup YYYYMMDD-HHMMSS`

**Interfaces:**
- Consumes: completed engine, store, AppKit controls, and current local generated library.
- Produces: documented behavior, recoverable clean local library, verified Desktop app, and published feature branch.

- [ ] **Step 1: Document Smart mapping and personal-library behavior**

Update README usage and conversion sections to state that Smart is the default, detected-key inference is heuristic, existing saved scores are not remapped, favourites are local, clearing preserves Aloha and original MIDIs, and Strict/Down/Up remain available. Update `docs/PRIVATE_SCORES.md` with the same storage and clearing boundaries.

- [ ] **Step 2: Run complete fresh verification**

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
git diff --check
codesign --verify --deep --strict --verbose=2 'build/Teyvat Virtuoso.app'
```

Expected: zero test failures, successful build, clean diff check, and a valid designated requirement.

- [ ] **Step 3: Commit documentation**

```zsh
git add README.md docs/PRIVATE_SCORES.md
git commit -m "docs: explain smart mapping and library controls"
```

- [ ] **Step 4: Back up and clear the active imported library**

Quit the running Desktop app. Resolve one timestamped sibling path, verify the source is exactly `/Users/philippsyrov/Library/Application Support/Teyvat Virtuoso`, and move that directory to the sibling backup. Do not delete the backup or any original MIDI.

- [ ] **Step 5: Install and visually verify the Desktop app**

Move the previous Desktop bundle to a recoverable `/private/tmp` backup, copy the freshly built bundle into `/Users/philippsyrov/Desktop/Teyvat Virtuoso.app`, and launch it. Verify the picker initially contains Aloha only, Smart is selected, a dropped MIDI displays a detected key, saving adds one local song, favourite toggling adds `♥` and reorders it, cancelling Clear changes nothing, and confirming Clear returns the picker to Aloha.

- [ ] **Step 6: Run one live GeForce NOW smoke test**

Open Genshin's instrument, play a short imported preview, focus GeForce NOW during the five-second lead-in, and verify keys visibly activate. If Accessibility is stale, refresh only Teyvat Virtuoso's existing toggle and repeat.

- [ ] **Step 7: Push the reviewed feature branch**

```zsh
git status -sb
git push -u origin feat/smart-mapping-library-favorites
```

Expected: clean branch tracking the remote feature branch; no `.mid` or `.midi` files tracked.
