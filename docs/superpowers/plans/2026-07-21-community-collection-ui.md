# Community Collection and Native Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an attributed, on-demand community arrangement collection, separate it from personal songs in a cleaner native sidebar UI, and publish downloadable macOS release assets.

**Architecture:** A focused `CommunityLibrary.swift` unit owns catalog models, remote-response validation, 15-key-to-21-key conversion, and Application Support caching. `GenshinLyrePlayerApp.swift` owns three native AppKit destinations and delegates all community data work to that unit. A metadata-only bundled catalog identifies curated remote arrangements without redistributing their note data.

**Tech Stack:** Swift 5, AppKit, Foundation `URLSession`, CoreGraphics keyboard events, Python `unittest`, GitHub Actions on macOS.

## Global Constraints

- Preserve the working MIDI engine, keyboard playback, saved per-song speed, favourites, and stable Accessibility bundle identity.
- Do not commit copyrighted community note data; bundle only metadata, attribution, and remote identifiers.
- Keep Community Collection, My Library, and Import MIDI visibly and structurally separate.
- Use native AppKit controls, system colours, and restrained spacing without third-party dependencies.
- Run `python3 -m unittest tests/test_play_score.py`, `./scripts/build_app.sh`, and `git diff --check` before completion.

---

### Task 1: Community catalog, conversion, and cache

**Files:**
- Create: `player/CommunityLibrary.swift`
- Create: `scores/community/catalog.json`
- Create: `tests/CommunityLibraryTests.swift`
- Modify: `tests/test_play_score.py`
- Modify: `scripts/build_app.sh`

**Interfaces:**
- Produces: `CommunityCatalogEntry`, `CommunitySourceSong`, `CommunityLibraryError`, and `CommunityScoreStore`.
- Produces: `CommunitySourceSong.makeScore() throws -> [ImportedScoreEvent]` and `CommunityScoreStore.cachedScore(for:)`.
- Consumes: `ImportedScoreEvent` from `MidiEngine.swift`.

- [ ] **Step 1: Write failing catalog and conversion tests**

Create Swift fixture tests that decode a source response containing `1Key0`, simultaneous `1Key2`/`1Key4`, and `1Key14`, then require conversion to `z`, a stable chord, and `q` with millisecond delays preserved. Add rejection cases for unknown keys, negative timestamps, empty notes, and unsafe cache filenames. Add a Python contract asserting the metadata catalog contains credits/source identifiers but no `songNotes` payloads.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```zsh
python3 -m unittest tests/test_play_score.py
```

Expected: failure because `CommunityLibrary.swift`, the catalog, and its contracts do not exist.

- [ ] **Step 3: Implement the minimal community data unit**

Define Codable catalog/source models, validate `1Key0...1Key14`, group equal absolute timestamps, convert the sequential natural-note indexes through `zxcvbnmasdfghjq`, cap emitted chords at the player's safe three-key limit, and convert absolute times into non-negative delays. Cache only converted score JSON plus attribution metadata beneath `Application Support/Teyvat Virtuoso/Community Scores` using sanitized catalog-owned filenames.

- [ ] **Step 4: Bundle the metadata catalog and compile it into the app**

Add the inspected curated entries with title, arranger when known, duration, remote filename, and source URL. Update `build_app.sh` to compile `CommunityLibrary.swift` and copy `community-catalog.json` into app Resources.

- [ ] **Step 5: Run focused tests and commit GREEN**

Run:

```zsh
python3 -m unittest tests/test_play_score.py
```

Expected: all community model and existing player tests pass.

Commit: `feat: add attributed community arrangement catalog`

### Task 2: Native sidebar and separated destinations

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `CommunityScoreStore`, `CommunityCatalogEntry`, and converted `[ImportedScoreEvent]` from Task 1.
- Preserves: `UserScoreStore`, `PlaybackController`, MIDI import options, favourite state, and saved per-song speed.

- [ ] **Step 1: Write failing UI source contracts**

Require a source-list sidebar with the exact destinations `Community Collection`, `My Library`, and `Import MIDI`; a content container that switches one destination at a time; per-song attribution and source action; a persistent Stop control; an Advanced mapping disclosure; and absence of the obsolete `Set Saved Speed` button.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `python3 -m unittest tests/test_play_score.py` and confirm the new navigation and attribution assertions fail against the stacked workbench.

- [ ] **Step 3: Build the native navigation shell**

Replace the single scroll document with an outer vertical stack containing an `NSSplitView`: a compact source-list sidebar and a content container. Construct and retain separate community, personal-library, and MIDI-import views. Keep the shared status text and Stop button in a persistent footer.

- [ ] **Step 4: Implement Community Collection interactions**

Render a searchable curated list with title, duration, arranger/source credit, local availability, and Download/Play. Fetch the catalog-owned remote identifier through `URLSession`, validate and cache through Task 1, and play cached scores through `PlaybackController`. Open source links through `NSWorkspace`. Surface network and validation errors in the shared status footer without replacing a valid cache.

- [ ] **Step 5: Polish My Library and Import MIDI**

Keep public-domain and personal songs in My Library only. Use one primary Play action, Favourite, and a compact actions menu for confirmed clearing. Place transpose, missing-note policy, merge tolerance, and speed inside a collapsed Advanced mapping disclosure. Rename imported actions to Preview and Save to My Library, while preserving automatic per-song speed persistence.

- [ ] **Step 6: Run tests, build, and commit GREEN**

Run:

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
```

Expected: tests pass and `build/Teyvat Virtuoso.app` is produced.

Commit: `feat: redesign app around community and personal libraries`

### Task 3: Credits, documentation, and downloadable releases

**Files:**
- Create: `scripts/package_release.sh`
- Create: `.github/workflows/release.yml`
- Modify: `README.md`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: the app bundle produced by `scripts/build_app.sh`.
- Produces: `dist/Teyvat-Virtuoso-macOS.zip` and `dist/Teyvat-Virtuoso-macOS.zip.sha256`.

- [ ] **Step 1: Write failing release and documentation contracts**

Require the package script and tag-triggered workflow, exact release filenames, full verification before packaging, GitHub Release upload commands, Community Collection attribution language, source links, downloadable-release instructions, and the ad-hoc-signing/Gatekeeper limitation.

- [ ] **Step 2: Run tests and verify RED**

Run `python3 -m unittest tests/test_play_score.py` and confirm the missing workflow/package/documentation assertions fail.

- [ ] **Step 3: Implement deterministic release packaging**

Build the app, recreate only repository-local `dist/`, package the `.app` with `ditto -c -k --sequesterRsrc --keepParent`, and write `shasum -a 256` output beside it. Never delete outside the explicit repository `dist` path.

- [ ] **Step 4: Add the tag release workflow**

On `v*` tags, use `macos-latest`, check out the repository, run the Python tests, execute the package script, and call `gh release create "$GITHUB_REF_NAME"` with both assets and generated release notes under `contents: write` permission.

- [ ] **Step 5: Update public documentation and credits**

Add a download-first installation section, first-open Gatekeeper instructions, Community Collection behavior and caching location, per-arranger/source attribution explanation, Genshin Music Nightly links, and the distinction between ad-hoc signing and future notarisation.

- [ ] **Step 6: Run tests, package, inspect, and commit GREEN**

Run:

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/package_release.sh
unzip -l dist/Teyvat-Virtuoso-macOS.zip
codesign -d --verbose=4 'build/Teyvat Virtuoso.app'
```

Expected: tests pass; ZIP contains the app bundle; checksum exists; signature reports `Identifier=com.philippsyrov.teyvat-virtuoso`.

Commit: `ci: publish downloadable macOS release assets`

### Task 4: Full verification and visual smoke test

**Files:**
- Modify only files requiring corrections discovered by verification.

**Interfaces:**
- Consumes: all completed implementation tasks.
- Produces: a verified app and release package ready for branch publication.

- [ ] **Step 1: Run the complete verifier**

Run:

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
git diff --check
git status --short
```

Expected: zero test failures, successful build, no whitespace errors, and only intentional changes.

- [ ] **Step 2: Launch and visually inspect the app**

Open the built app, confirm all three sidebar destinations switch correctly, labels do not truncate at minimum size, Community credits remain readable, Advanced mapping starts collapsed, Stop is always visible, and dark-mode contrast is clear.

- [ ] **Step 3: Exercise safe non-keyboard interactions**

Verify catalog filtering, source-link availability, a community download/cache attempt, cached-state presentation, MIDI drag/drop, and My Library selection. Do not send keyboard events unless GeForce NOW is deliberately focused.

- [ ] **Step 4: Commit any verification corrections**

Commit only if verification required changes, using `fix: polish community collection release`.
