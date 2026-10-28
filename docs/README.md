# Documentation

## User guides

- [Instrument key mappings](Genshin_Instrument_Key_Mappings.md): the three-row lyre layout and worked key examples.
- [MIDI candidate preflight](MIDI_Candidate_Preflight.md): how to judge whether a source can survive the 21-key reduction.
- [Private score workflow](PRIVATE_SCORES.md): where private MIDI belongs, copyright, and what the app saves locally.

## Developer guide

The root [README](../README.md) covers installing and building from source. The source is split between the native Swift app under `player/`, MIDI utilities under `scripts/`, and dependency-free tests under `tests/`. The MIDI analysis and conversion scripts need `mido`, pinned in `scripts/requirements.txt`.

Release history: [CHANGELOG](../CHANGELOG.md).
