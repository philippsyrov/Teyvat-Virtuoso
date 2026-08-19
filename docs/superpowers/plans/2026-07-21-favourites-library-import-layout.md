# Favourites, Library Cards, and Import Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add click-only community discovery, persistent cross-library favourites, card-based My Library playback controls, and a stable Import MIDI layout.

**Architecture:** Add a focused Application Support `FavoriteStore` for IDs from the bundled library, local imports, and the metadata-only community catalog. Keep AppKit rendering in the existing application delegate, with a small playback-state callback so all card rails can redraw their own primary action as `Play`, `Download`, or `Stop`.

**Tech Stack:** Native macOS Swift, AppKit, Foundation Codable, Python unittest, existing shell build script.

## Global Constraints

- Community arrangements remain metadata-only in the repository; note data downloads only after a click.
- Preserve original source attribution and the user-controlled browser handoff.
- Keep source timing, simultaneous chords, and the existing footer Stop action.
- Before a commit, run `python3 -m unittest tests/test_play_score.py` and `./scripts/build_app.sh`.

---

### Task 1: Shared favourite persistence

**Files:**
- Create: `player/FavoriteStore.swift`
- Create: `tests/FavoriteStoreTests.swift`
- Modify: `tests/test_play_score.py`
- Modify: `scripts/build_app.sh`

**Interfaces:**
- Produces: `FavoriteStore.favoriteIDs() -> Set<String>`, `FavoriteStore.setFavorite(_ id: String, isFavorite: Bool) throws`, and `FavoriteStore.sorted<T>(_ items: [T], id: (T) -> String) -> [T]`.

- [ ] **Step 1: Write the failing store-contract test**

```swift
let store = FavoriteStore(root: root)
try store.setFavorite("community:illusionary-daytime", isFavorite: true)
try store.setFavorite("library:aloha_oe", isFavorite: true)
assert(store.favoriteIDs() == ["community:illusionary-daytime", "library:aloha_oe"])
```

- [ ] **Step 2: Run the failing test**

Run: `swiftc player/FavoriteStore.swift tests/FavoriteStoreTests.swift -o "$TMPDIR/favorite-store-tests" && "$TMPDIR/favorite-store-tests"`

Expected: FAIL because `FavoriteStore.swift` does not exist.

- [ ] **Step 3: Implement the atomic manifest store**

```swift
final class FavoriteStore {
    func favoriteIDs() -> Set<String>
    func setFavorite(_ id: String, isFavorite: Bool) throws
}
```

Store a sorted JSON array at `Application Support/Teyvat Virtuoso/favorites.json`, reject empty IDs, and atomically replace the manifest.

- [ ] **Step 4: Verify the focused test passes**

Run: `swiftc player/FavoriteStore.swift tests/FavoriteStoreTests.swift -o "$TMPDIR/favorite-store-tests" && "$TMPDIR/favorite-store-tests"`

Expected: `FavoriteStoreTests passed`.

### Task 2: Community discovery, hearts, and active row actions

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `FavoriteStore` from Task 1 and `PlaybackController.onPlaybackChange: (String?) -> Void`.
- Produces: an external browse button, favourite-first visible community cards, and card-local `Stop` state.

- [ ] **Step 1: Write failing source-contract assertions**

```python
self.assertIn('Browse all Sky Music sheets', source)
self.assertIn('https://sky-music.github.io/', source)
self.assertIn('community:', source)
self.assertIn('actionTitle = isActive ? "Stop"', source)
```

- [ ] **Step 2: Run the focused test**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_community_screen_exposes_attribution_download_and_source_actions`

Expected: FAIL because the browse action and active action title do not exist.

- [ ] **Step 3: Implement minimal community actions**

Add the browse button below the community introduction, use `NSWorkspace.shared.open` only for that HTTPS page and existing row source URLs, and put a 36-point heart between `Open Source` and the fixed 92-point primary button. Sort visible rows with favourite IDs before ordinary entries while preserving catalog order.

- [ ] **Step 4: Verify the focused test passes**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_community_screen_exposes_attribution_download_and_source_actions`

Expected: PASS.

### Task 3: My Library cards and row-level Stop control

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `FavoriteStore` from Task 1 and active playback ID from Task 2.
- Produces: `rebuildLibraryRows()` and card actions for every bundled and local saved score.

- [ ] **Step 1: Write failing source-contract assertions**

```python
self.assertIn('private let libraryRowsStack = NSStackView()', source)
self.assertIn('func rebuildLibraryRows()', source)
self.assertIn('library:', source)
self.assertIn('title: "♥"', source)
```

- [ ] **Step 2: Run the focused test**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_native_app_exposes_smart_mapping_and_personal_library_controls`

Expected: FAIL because the card stack and shared favourite identifiers do not exist.

- [ ] **Step 3: Implement the card stack**

Replace the picker/subtitle/button arrangement with one full-width card per `Song`; use one-line title and subtitle labels, a 36-point heart, and a fixed 92-point Play/Stop control. Keep the existing import-clear operation in a compact menu below the cards. Make both the footer Stop and the active row call the same `stopPlayback()` method.

- [ ] **Step 4: Verify the focused test passes**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_native_app_exposes_smart_mapping_and_personal_library_controls`

Expected: PASS.

### Task 4: Stable Import MIDI card layout

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Produces: `makeImportCard(_:) -> NSView` and a non-compressing advanced disclosure control.

- [ ] **Step 1: Write failing source-contract assertions**

```python
self.assertIn('advancedMappingDisclosure.setContentCompressionResistancePriority(.required, for: .horizontal)', source)
self.assertIn('makeImportCard', source)
self.assertIn('advancedMappingCard', source)
```

- [ ] **Step 2: Run the focused test**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_import_screen_hides_advanced_mapping_until_requested`

Expected: FAIL because the full-width card and required disclosure priority do not exist.

- [ ] **Step 3: Implement full-width cards**

Wrap source summary, enabled tracks, advanced controls, and actions in the common page column. Make the disclosure keep its intrinsic width, and put the advanced `NSGridView` inside its own full-width card with labels in a fixed leading column and controls aligned in a second column.

- [ ] **Step 4: Verify the focused test passes**

Run: `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_import_screen_hides_advanced_mapping_until_requested`

Expected: PASS.

### Task 5: Build, install, and rename project presentation

**Files:**
- Modify: `scripts/build_app.sh` only if the new store source must be compiled.
- Rename after verification: local repository directory and GitHub repository presentation from `TeyvatVirtuoso` to `Teyvat Virtuoso`.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: a verified installed application and a repository whose visible name contains a space.

- [ ] **Step 1: Run the full automated checks**

Run: `python3 -m unittest tests/test_play_score.py && ./scripts/build_app.sh`

Expected: every test passes and `Built .../Teyvat Virtuoso.app` is printed.

- [ ] **Step 2: Validate the bundle and live UI**

Run: `codesign --verify --deep --strict 'build/Teyvat Virtuoso.app'`

Expected: exit status 0; visually verify community, library, and import pages at normal width.

- [ ] **Step 3: Replace the Desktop test bundle recoverably**

Move the existing Desktop bundle to `Teyvat Virtuoso.previous.app`, copy the verified bundle into `Teyvat Virtuoso.app`, and open the new exact path.

- [ ] **Step 4: Rename repository presentation only after the installed build opens**

Rename the local repository directory with `mv` and rename the GitHub repository through its authenticated repository settings or `gh repo rename 'Teyvat Virtuoso'`. Preserve the remote and run `git remote -v` after the remote rename.
