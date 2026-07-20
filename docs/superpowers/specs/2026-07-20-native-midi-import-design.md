# Native MIDI Import Design

## Goal

Turn Teyvat Virtuoso from a prepared-score picker into a native macOS MIDI workflow: drop or choose a MIDI, inspect its tracks, configure a safe lyre reduction, preview the result, play it in Genshin, and optionally save the generated score locally.

## User flow

The window keeps the curated song picker at the top and adds an Import MIDI section. A user drops a `.mid` or `.midi` file, sees duration, note count, natural-note fit, and one checkbox per musical track, then chooses transpose, missing-note handling, chord merge tolerance, and playback speed. Play Imported uses the existing five-second focus countdown. Save to Library stores only generated JSON under Application Support; the original private MIDI is never copied or bundled.

## Architecture

`MidiEngine.swift` owns a dependency-free Standard MIDI File parser, tempo conversion, track analysis, and the deterministic MIDI-to-21-key reduction. `GenshinLyrePlayerApp.swift` owns AppKit controls and drag-and-drop. `PlaybackController` accepts both bundled JSON scores and in-memory imported scores. User-saved reductions use the same JSON schema as bundled scores.

## Mapping rules

- The playable pitch window is three natural-note octaves mapped low `ZXCVBNM`, middle `ASDFGHJ`, and high `QWERTYU`.
- Notes outside the three-octave window are folded by octaves before mapping.
- Chromatic notes are either skipped, snapped down by semitones to the nearest natural, or snapped up; the UI never hides this choice.
- One shared transpose applies to every enabled track.
- Notes whose source onsets fall within the selected merge tolerance become one event, capped at three distinct keys.
- Source tempo changes and rests are preserved.

## Persistence and safety

Bundled public-domain scores remain read-only. Imported reductions are written to `~/Library/Application Support/Teyvat Virtuoso/Scores/` with a local manifest. Private MIDI sources and commercial arrangements are not committed or copied into the public repository. Malformed MIDI and unsupported SMPTE timing return visible errors and never emit key events.

## Verification

Swift engine tests cover MIDI parsing, running status, tempo conversion, track selection, transposition, missing-note policies, octave folding, chord merging, and JSON-safe output. Existing player tests remain green, the app compiles, and Sudden Snow plus the supplied pirate MIDI files receive read-only import smoke tests before the Desktop app is replaced.
