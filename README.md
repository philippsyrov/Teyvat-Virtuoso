# Teyvat Virtuoso

Teyvat Virtuoso is a lightweight native macOS companion for Genshin Impact players who stream the game through NVIDIA GeForce NOW. It converts Standard MIDI files into live performances on Genshin's 21-key instruments: drop in a MIDI, choose its musical tracks and mapping rules, then focus the GeForce NOW window and let the app perform it.

The app also works with other focused game windows that accept normal Mac keyboard input, including compatible iPhone Mirroring setups. It is local-first: MIDI analysis, score conversion, saved arrangements, and keyboard playback all happen on your Mac.

## Features

- Native drag-and-drop and file-picker support for `.mid` and `.midi` files
- Per-track selection with note range and chord-density information
- Automatic shared-transpose recommendation based on natural-note fit
- Smart key-aware handling for unavailable black-key notes, with strict/up/down fallbacks
- Adjustable chord-merging tolerance for near-simultaneous source notes
- Source-tempo preservation with selectable playback speed from 90% through 200%
- Per-song saved timing, including a one-click speed assignment for legacy library entries
- Real simultaneous key-down events for chords of up to three notes
- Five-second focus countdown and interruptible playback
- Local saved-score library with persistent favourites and confirmed clearing
- A bundled, protected public-domain Aloha ʻOe demonstration arrangement

## Instrument layout

Genshin's lyre-style interface exposes three octaves of seven natural notes:

```text
High:   Q W E R T Y U
Middle: A S D F G H J
Low:    Z X C V B N M
```

Teyvat Virtuoso folds source pitches by octaves into this range. Smart mapping estimates a major or minor key from the enabled tracks, then chooses the adjacent natural note that best fits that key and the local melodic motion. Strict, Snap down, and Snap up remain available for direct comparison.

## Requirements

- macOS 13 or newer
- Genshin Impact through NVIDIA GeForce NOW for macOS, or another game window that accepts normal Mac keyboard input
- Accessibility permission for Teyvat Virtuoso under **System Settings → Privacy & Security → Accessibility**
- Apple Command Line Tools when building from source

## Build from source

```zsh
git clone https://github.com/philippsyrov/TeyvatVirtuoso.git
cd TeyvatVirtuoso
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
open 'build/Teyvat Virtuoso.app'
```

The build script creates a self-contained native app bundle under `build/`. The running app does not require Python or third-party Swift packages.

## Usage

1. Open `Teyvat Virtuoso.app` and grant Accessibility permission if macOS requests it.
2. Drag a MIDI onto the Import MIDI panel, or choose **Open MIDI…**.
3. Review the detected tracks. Disable percussion, duplicate orchestration, or parts that make the reduction too dense.
4. Review the recommended transpose and detected key. **Smart — key-aware** is selected automatically; compare the legacy policies when a particular arrangement benefits from them.
5. Choose a chord merge tolerance and playback timing.
6. Press **Play Imported**, then focus the open Genshin instrument during the five-second countdown.
7. If the reduction works well, choose **Save to Library**. Only the generated key-event JSON is saved; the original MIDI is not copied.
8. Mark imported performances as favourites to move them to the top of the selector. **Clear Imported Library…** removes generated saved arrangements after confirmation while preserving Aloha and every original MIDI.

If keyboard playback stops after replacing or rebuilding the app, toggle Teyvat Virtuoso off and on again under **System Settings → Privacy & Security → Accessibility**, then reopen it. macOS can retain an approval for an older local build even when the app name is unchanged.

## How MIDI conversion works

The native engine parses Standard MIDI headers, track chunks, running status, tempo changes, track names, and note-on events directly in Swift. It then:

1. Filters the selected source tracks.
2. Applies one shared semitone transposition.
3. Detects a likely major or natural-minor key and resolves unavailable chromatic pitches using the selected policy.
4. Folds notes by octaves into the three-row playable window.
5. Converts source ticks through the authored tempo map.
6. Merges nearby onsets into stable chords of no more than three distinct keys.
7. Emits the same compact JSON event format used by bundled performances.

Key detection is a deterministic musical estimate, not a guarantee: dense orchestral MIDIs, percussion-like pitched tracks, and key changes can mislead one global profile. This process also cannot recreate notes the in-game instrument does not have. A high natural-note fit is useful, but recognisable results still depend on choosing the right melody and accompaniment tracks.

Saved and bundled performances already contain resolved keyboard events. Changing Smart, Strict, Down, or Up affects the current imported MIDI preview and future save only; it never rewrites an existing library entry.

## Project structure

```text
player/
  GenshinLyrePlayerApp.swift   Native AppKit interface and keyboard playback
  MidiEngine.swift             Standard MIDI parser and lyre reduction engine
  UserScoreStore.swift         Local favourites and generated-score persistence
scores/public-domain/          Redistributable example arrangements
scripts/build_app.sh           Reproducible local app build
scripts/preflight_midi.py      Optional detailed command-line MIDI report
tests/                         Swift engine fixtures and app/build contracts
docs/                          Mapping, privacy, design, and implementation notes
```

## Private scores and copyright

Downloaded or purchased MIDI files belong under the ignored `scores/private/` folder. Teyvat Virtuoso's local library stores generated score JSON under `~/Library/Application Support/Teyvat Virtuoso/`; it does not place private source files inside the repository or app bundle.

Only publish MIDI sources or derivative arrangements when you have the right to redistribute them.

## Development

Run the complete verification before committing:

```zsh
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
git diff --check
```

Contributions should preserve source timing, keep chromatic-note changes explicit, validate every generated key, and include a failing regression test before implementation.

## Credits

The workflow was informed by [sabihoshi/GenshinLyreMidiPlayer](https://github.com/sabihoshi/GenshinLyreMidiPlayer), an MIT-licensed Windows project. Teyvat Virtuoso is an independent native macOS implementation and does not use that project's Windows UI or keyboard-input stack.

## License and disclaimer

The application source is available under the [MIT License](LICENSE).

Teyvat Virtuoso is an unofficial fan-made tool. It is not affiliated with, endorsed by, or sponsored by HoYoverse. Genshin Impact and related names are trademarks of their respective owners. Automated input may be restricted by a game's terms or platform rules; users are responsible for deciding where and how to use the app.
