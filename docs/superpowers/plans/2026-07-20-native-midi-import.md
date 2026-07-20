# Native MIDI Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dependency-free MIDI drag-and-drop, track selection, safe note reduction, playback, and local score saving to Teyvat Virtuoso.

**Architecture:** A focused Swift engine parses Standard MIDI files and converts chosen tracks into the existing score-event schema. The AppKit layer presents analysis and settings, then passes in-memory or saved JSON scores to the existing playback controller.

**Tech Stack:** Swift 6, AppKit, Foundation, CoreGraphics, Python `unittest` as the build-test harness.

## Global Constraints

- macOS 13.0 or newer.
- No runtime Python or third-party Swift package dependency.
- Do not copy private MIDI files into the application bundle or Git repository.
- Preserve source timing and require an explicit chromatic-note policy.
- Limit emitted chords to three supported Genshin keys.

---

### Task 1: MIDI parser and analysis

**Files:**
- Create: `player/MidiEngine.swift`
- Create: `tests/MidiEngineTests.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Produces: `MidiDocument.parse(data:) throws -> MidiDocument`
- Produces: `MidiTrackInfo` with index, name, notes, range, and chord count
- Produces: `MidiDocument.durationMs` and `bestTranspose`

- [ ] Write a Swift fixture test that builds a two-track MIDI containing a tempo event, running status, chords, and named tracks.
- [ ] Add a Python harness test that compiles and runs the Swift fixture test; run it and confirm failure because `MidiEngine.swift` is absent.
- [ ] Implement bounded big-endian reads, variable-length quantities, channel-event parsing, meta tempo/name parsing, and tick-to-millisecond conversion.
- [ ] Run the engine fixture and full Python suite; expect all tests to pass.

### Task 2: Deterministic lyre reduction

**Files:**
- Modify: `player/MidiEngine.swift`
- Modify: `tests/MidiEngineTests.swift`

**Interfaces:**
- Consumes: `MidiDocument` and `MidiImportOptions`
- Produces: `MidiDocument.makeScore(options:) -> [ImportedScoreEvent]`
- Produces: `MissingNotePolicy.skip`, `.down`, and `.up`

- [ ] Add failing fixtures for track selection, shared transpose, octave folding, all missing-note policies, merge tolerance, duplicate removal, and three-key chord caps.
- [ ] Run the engine fixture and confirm assertion failures are caused by missing reduction behavior.
- [ ] Implement the smallest deterministic reduction satisfying the tests while preserving source onset gaps.
- [ ] Run the engine fixture and full suite; expect all tests to pass.

### Task 3: Native import UI and playback

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `scripts/build_app.sh`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `MidiDocument.parse(data:)` and `makeScore(options:)`
- Produces: drag/drop and Open MIDI actions, track toggles, transpose/policy/merge controls, analysis summary, and `PlaybackController.play(score:title:at:)`

- [ ] Add failing source-contract tests for `.mid/.midi` drag types, Open MIDI, track checkboxes, three mapping policies, merge tolerance, and in-memory playback.
- [ ] Compile the app and confirm the tests fail because the controls and engine source are not wired.
- [ ] Implement the import panel, drag destination, file picker, dynamic track controls, analysis summary, and in-memory playback path.
- [ ] Update the build to compile both Swift source files and run the full suite plus app build.

### Task 4: Local library and public documentation

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `README.md`
- Modify: `docs/PRIVATE_SCORES.md`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Produces: `UserScoreStore.save(title:events:) throws -> Song`
- Produces: merged bundled and local song list without copying source MIDI

- [ ] Add failing tests for Application Support storage, generated JSON persistence, custom manifest loading, and private-source wording.
- [ ] Implement local JSON score storage and reload the picker after Save to Library.
- [ ] Rewrite the README with a professional overview, feature status, build instructions, architecture, limitations, privacy, contributing, credits, and trademark disclaimer.
- [ ] Run unit tests, app build, `git diff --check`, and read-only smoke imports for Sudden Snow and He's a Pirate.
- [ ] Commit the complete verified feature on `feat/native-midi-import`.
