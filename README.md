# Teyvat Virtuoso

Teyvat Virtuoso is a lightweight native macOS companion for Genshin Impact players who stream the game through NVIDIA GeForce NOW. It converts Standard MIDI files into live performances on Genshin's 21-key instruments: drop in a MIDI, choose its musical tracks and mapping rules, then focus the GeForce NOW window and let the app perform it.

The app also works with other focused game windows that accept normal Mac keyboard input, including compatible iPhone Mirroring setups. It is local-first: MIDI analysis, score conversion, saved arrangements, and keyboard playback all happen on your Mac.

## Features

- Native drag-and-drop and file-picker support for MIDI plus Sky Music `.txt`/`.json` sheets
- Per-track selection with note range and chord-density information
- Manual shared transposition with live natural-note-fit feedback
- Smart key-aware handling for unavailable black-key notes, with strict/up/down fallbacks
- Adjustable chord-merging tolerance for near-simultaneous source notes
- Source-tempo preservation with selectable playback speed from 90% through 200%
- Expandable per-song speed sliders that persist imported performances from 90% through 200%
- Real simultaneous key-down events for chords of up to three notes
- Five-second focus countdown, card-level Stop, and offline generated-tone Listen previews
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

## Download

Download the latest signed macOS arm64 ZIP from [GitHub Releases](https://github.com/philippsyrov/Teyvat-Virtuoso/releases/latest), extract it, and open **Teyvat Virtuoso.app**.

## Build from source

```zsh
git clone https://github.com/philippsyrov/Teyvat-Virtuoso.git
cd Teyvat-Virtuoso
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
open 'build/Teyvat Virtuoso.app'
```

The build script creates a self-contained native app bundle under `build/`. The running app does not require Python or third-party Swift packages.

## Usage

1. Open `Teyvat Virtuoso.app` and grant Accessibility permission if macOS requests it.
2. Drag a MIDI or exported Sky Music `.txt`/`.json` sheet onto Import Score, or choose **Open Score…**.
3. Review the detected tracks. Disable percussion, duplicate orchestration, or parts that make the reduction too dense.
4. Every newly opened MIDI starts raw: **+0**, **Strict — skip black keys**, **Merge Off**, and **Original 100%**. Change those controls only when the source needs reduction.
5. Press **Preview**, then focus the open Genshin instrument during the five-second countdown. The same button becomes **Stop** during countdown and playback.
6. If the reduction works well, choose **Save to My Library**. Only the generated key-event JSON is saved; the original MIDI is not copied.
7. In **My Library**, expand a song's **Speed** control to adjust that one saved performance in 5% steps. Mark favourites to move them to the top. **Clear Imported Library…** removes generated saved arrangements after confirmation while preserving Aloha and every original MIDI.

If keyboard playback stops after replacing or rebuilding the app, toggle Teyvat Virtuoso off and on again under **System Settings → Privacy & Security → Accessibility**, then reopen it. macOS can retain an approval for an older local build even when the app name is unchanged.

## How MIDI conversion works

The native engine parses Standard MIDI headers, track chunks, running status, tempo changes, track names, and note-on events directly in Swift. It then:

1. Filters the selected source tracks.
2. Applies one shared semitone transposition.
3. Resolves unavailable chromatic pitches using the selected policy; Smart additionally estimates a likely major or natural-minor key.
4. Folds notes by octaves into the three-row playable window.
5. Converts source ticks through the authored tempo map.
6. Optionally merges nearby onsets, while Merge Off preserves distinct source onset times.
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
