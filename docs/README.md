# Documentation

Start here for the current app. The dated design and implementation files are retained as history, not as setup instructions.

## User guides

- [Instrument key mappings](Genshin_Instrument_Key_Mappings.md) — the three-row lyre layout and worked key examples.
- [MIDI candidate preflight](MIDI_Candidate_Preflight.md) — how to judge whether a source can survive the 21-key reduction.
- [Private score workflow](PRIVATE_SCORES.md) — where private MIDI belongs and what the app saves locally.

## Developer guide

The root [README](../README.md) contains build, verification, architecture, and release instructions. The source is split between the native Swift app under `player/`, MIDI utilities under `scripts/`, and dependency-free tests under `tests/`.

## Design history

- [`superpowers/specs/`](superpowers/specs/) records earlier product decisions.
- [`superpowers/plans/`](superpowers/plans/) records the corresponding implementation steps.

Historical files may describe an older interface. Use the root README and the user guides above for current behaviour.
