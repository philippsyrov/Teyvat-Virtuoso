# Full Sky Music Catalogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Sky Music's metadata-only full legacy catalogue, import its JSON sheets directly, and provide a local lyre Listen preview without a footer Stop button.

**Architecture:** Generate a safe bundled metadata file from Sky Music's public index, merge it with richer curated metadata, and render only a page of matching rows at once. Reuse the existing strict `CommunitySourceSong` converter for remote and local JSON sheets. Add a small AVFoundation oscillator/scheduler that consumes already validated `ImportedScoreEvent` values and remains separate from keyboard playback.

**Tech Stack:** Swift/AppKit, AVFoundation, Foundation, Python unittest, JSON metadata.

## Global Constraints

- Bundle metadata only; never bundle community `songNotes`, original `.txt` sheets, MIDI, or game audio.
- Fetch/cache an arrangement only after an explicit Download click.
- Preserve strict 15-key source validation, one-to-three-key chord cap, and source attribution.
- Use generated offline tones, not copied game samples.
- Keep every non-obvious conversion decision commented.
- Verify with `python3 -m unittest tests/test_play_score.py` and `./scripts/build_app.sh` before committing.

---

### Task 1: Full metadata catalogue

**Files:**
- Create: `scripts/build_community_catalog.py`
- Modify: `scores/community/catalog.json`
- Modify: `player/CommunityLibrary.swift`
- Modify: `tests/CommunityLibraryTests.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Produces `CommunityCatalogEntry(id:title:arranger:durationSeconds:remoteFile:sourceURL:)` entries with optional duration.
- Consumes Sky Music list records shaped `{ "name": String, "file": String }`.

- [ ] **Step 1: Write the failing metadata test**

```swift
expectCommunity(fullCatalog.songs.count >= 600, "expected complete metadata-only catalogue")
expectCommunity(fullCatalog.songs.allSatisfy { !$0.remoteFile.isEmpty }, "expected remote files")
```

- [ ] **Step 2: Run the community test and confirm it fails because the curated catalogue has fewer than 600 records.**

Run: `python3 -m unittest tests/test_play_score.py`

- [ ] **Step 3: Add `scripts/build_community_catalog.py`**

```python
for source in public_index:
    identifier = sha256(source["file"].encode()).hexdigest()[:20]
    output.append({"id": f"sky-{identifier}", "title": source["name"], "arranger": None,
                   "durationSeconds": None, "remoteFile": source["file"], "sourceURL": library_url})
```

Merge richer existing curated records by remote filename so researched title, arranger, and duration survive. Emit sorted JSON with no note fields.

- [ ] **Step 4: Regenerate `scores/community/catalog.json` from the fetched public index and run the test.**

Run: `python3 scripts/build_community_catalog.py /private/tmp/sky-librarySongsList.json scores/community/catalog.json && python3 -m unittest tests/test_play_score.py`

Expected: metadata contracts pass and the file contains no `songNotes` field.

- [ ] **Step 5: Make `durationSeconds` optional and render unknown duration as `Sky Music community` rather than `0:00`.**

```swift
let details = entry.durationSeconds.map { "\(formatDuration(Double($0) * 1_000)) · \(entry.creditLine)" } ?? entry.creditLine
```

- [ ] **Step 6: Commit the catalogue layer.**

```bash
git add scripts/build_community_catalog.py scores/community/catalog.json player/CommunityLibrary.swift tests/CommunityLibraryTests.swift tests/test_play_score.py
git commit -m "feat: add full Sky Music metadata catalogue"
```

### Task 2: Bounded discovery rows and direct sheet imports

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Adds `communityVisibleLimit`, `loadMoreCommunityRows(_:)`, and a matching-result label.
- Adds `loadScore(_:)` which dispatches MIDI to `loadMidi(_:)` and `.txt`/`.json` to `loadSkyMusicSheet(_:)`.

- [ ] **Step 1: Add failing source-contract assertions.**

```python
self.assertIn("communityVisibleLimit", source)
self.assertIn('"Load more"', source)
self.assertIn('"txt", "json"', source)
self.assertIn("loadSkyMusicSheet", source)
```

- [ ] **Step 2: Run the harness and confirm these assertions fail.**

Run: `python3 -m unittest tests/test_play_score.py`

- [ ] **Step 3: Limit cards and add Load more.**

```swift
let rows = Array(visibleCommunityEntries.prefix(communityVisibleLimit))
if visibleCommunityEntries.count > rows.count {
    communityRowsStack.addArrangedSubview(NSButton(title: "Load more", target: self, action: #selector(loadMoreCommunityRows)))
}
```

Reset the limit on new search; use a 50-row batch. Preserve current favourite-first order and row tags against the rendered subset.

- [ ] **Step 4: Generalise the file drop and picker.**

```swift
panel.allowedContentTypes = ["mid", "midi", "txt", "json"].compactMap(UTType.init(filenameExtension:))
if ["txt", "json"].contains(url.pathExtension.lowercased()) { loadSkyMusicSheet(url) } else { loadMidi(url) }
```

Change all visible copy to **Import Score** and accept those same extensions in drag handling.

- [ ] **Step 5: Reuse strict source conversion for local sheets.**

```swift
let source = try CommunitySourceSong.decodeResponse(Data(contentsOf: url))
let events = try source.makeScore()
loadImportedScore(title: source.name, filename: url.lastPathComponent, events: events)
```

Keep MIDI document-specific controls disabled/hidden for a direct sheet; Preview and Save use the converted events. On any read/decode/validation error, retain the previously loaded score and show a Sky Music sheet-format explanation.

- [ ] **Step 6: Run the full test harness.**

Run: `python3 -m unittest tests/test_play_score.py`

Expected: all existing and new contracts pass.

- [ ] **Step 7: Commit the import/discovery layer.**

```bash
git add player/GenshinLyrePlayerApp.swift tests/test_play_score.py
git commit -m "feat: import Sky Music sheets on demand"
```

### Task 3: Offline lyre Listen preview and footer cleanup

**Files:**
- Create: `player/LyrePreviewPlayer.swift`
- Create: `tests/LyrePreviewPlayerTests.swift`
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `scripts/build_app.sh`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- `LyrePreviewPlayer.play(score:title:id:)`, `stop()`, `onPlaybackChange`.
- `LyrePreviewPlanner.events(score:) -> [(timeMs: Int, frequencies: [Double])]` converts the three 7-note keyboard rows into C3–B5-style generated tones while preserving group timing.

- [ ] **Step 1: Write deterministic planner tests.**

```swift
let events = LyrePreviewPlanner.events(score: [ImportedScoreEvent(delayMs: 100, keys: ["z", "c"]), ImportedScoreEvent(delayMs: 200, keys: ["q"])])
expectPreview(events[0].timeMs == 100 && events[0].frequencies.count == 2, "expected timed chord")
expectPreview(events[1].timeMs == 300, "expected cumulative schedule")
```

- [ ] **Step 2: Run the new Swift test and confirm it fails before implementation.**

Run: `swiftc player/MidiEngine.swift player/LyrePreviewPlayer.swift tests/LyrePreviewPlayerTests.swift -o /tmp/lyre-preview-tests`

Expected: compilation fails because `LyrePreviewPlayer.swift` does not exist.

- [ ] **Step 3: Implement the generated-tone preview player.**

Use AVAudioEngine with an `AVAudioSourceNode` and per-note sine envelopes. Schedule `DispatchWorkItem`s from the planner; preserve chords and cancel all pending work/items on `stop()`. Call the same status and playback-change closures on the main queue. The implementation must never access CoreGraphics, keyboard events, or Genshin.

- [ ] **Step 4: Add row-level Listen controls.**

Use the fixed action rail as `[Open Source, heart, Listen, Play]` for community rows and `[heart, Listen, Play]` for library rows. The active preview's Listen title becomes Stop; the active keyboard Play title independently becomes Stop. Starting either mode stops the other so a score cannot create overlapping audio/key streams.

- [ ] **Step 5: Remove only the footer Stop control.**

```swift
row.addArrangedSubview(statusLabel)
// Do not add a footer stop button; active card controls own stopping.
```

Keep the footer and status label for clear playback feedback.

- [ ] **Step 6: Compile both app and audio tests.**

Run: `swiftc player/MidiEngine.swift player/LyrePreviewPlayer.swift tests/LyrePreviewPlayerTests.swift -o /tmp/lyre-preview-tests && /tmp/lyre-preview-tests && ./scripts/build_app.sh`

Expected: `LyrePreviewPlayerTests passed` and `Built .../Teyvat Virtuoso.app`.

- [ ] **Step 7: Commit the preview layer.**

```bash
git add player/LyrePreviewPlayer.swift tests/LyrePreviewPlayerTests.swift player/GenshinLyrePlayerApp.swift scripts/build_app.sh tests/test_play_score.py
git commit -m "feat: preview scores with offline lyre tones"
```

### Task 4: Final validation and handoff

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document that Community scores are on-demand, JSON sheets can be imported, and Listen is an approximate offline preview.**

- [ ] **Step 2: Run the full required verification.**

Run: `python3 -m unittest tests/test_play_score.py && ./scripts/build_app.sh`

Expected: all tests pass and a signed app bundle is printed.

- [ ] **Step 3: Inspect the exact diff and status.**

Run: `git diff --check HEAD~4..HEAD && git status --short`

Expected: no whitespace errors; only intentional files plus pre-existing `Unknown.jpeg` remain untracked.

- [ ] **Step 4: Commit documentation if it changed.**

```bash
git add README.md
git commit -m "docs: explain on-demand score imports and listen preview"
```
