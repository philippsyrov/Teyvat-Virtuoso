<p align="center">
  <img src="assets/AppIcon-Paimon-Lyre.jpeg" alt="Teyvat Virtuoso app icon" width="128">
</p>

<h1 align="center">Teyvat Virtuoso</h1>

<p align="center">Play MIDI files on the Genshin Impact lyre, natively on macOS.</p>

<p align="center">
  <a href="https://github.com/philippsyrov/Teyvat-Virtuoso/releases/latest"><img src="https://img.shields.io/github/v/release/philippsyrov/Teyvat-Virtuoso?style=flat&color=555" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-555?style=flat" alt="macOS 13+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/philippsyrov/Teyvat-Virtuoso?style=flat&color=555" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://github.com/philippsyrov/Teyvat-Virtuoso/releases/latest">Download</a> ·
  <a href="docs/README.md">Docs</a> ·
  <a href="https://github.com/philippsyrov/Teyvat-Virtuoso/issues">Issues</a>
</p>

**Teyvat Virtuoso is a native macOS app that turns a MIDI file or Sky Music sheet into key presses for the 21-key Genshin Impact lyre and plays them into the focused game window.** Parsing, mapping, saved arrangements and keyboard playback all run locally; it is built for NVIDIA GeForce NOW on macOS and also works with other focused windows that accept normal Mac keyboard input.

<p align="center">
  <img src="assets/screenshots/library.png" alt="Teyvat Virtuoso library with saved Genshin songs and Play controls" width="88%">
</p>

| Feature | What it does |
| --- | --- |
| **MIDI and Sky Music import** | Drag-and-drop or open Standard MIDI plus Sky Music `.txt` / `.json` sheets from the app. |
| **Track-aware reduction** | Enable the melody and accompaniment tracks you want, with note-range and chord-density hints per track. |
| **Smart key mapping** | Estimates major or minor context and maps unavailable black keys deliberately instead of at random; Strict handling is the default. |
| **Real chords and tempo** | Sends up to three simultaneous key-down events, keeps the source tempo, and plays back from 90% to 200%. |
| **Focus, preview, stop** | Five-second countdown before playback so you can click the game window, a Stop button on each card, and offline tone previews. |
| **Local library** | Saves generated performances, favourites and per-song speed in Application Support, plus a bundled public-domain demo. |
| **Community Collection** | Browse a curated catalog of attributed Sky Music arrangements; a song's notes download only when you choose it. |
| **Export MIDI** | Writes a downloaded arrangement out as a standard editable `.mid` file in Downloads. |

## Install

Download the latest build from [GitHub Releases](https://github.com/philippsyrov/Teyvat-Virtuoso/releases/latest). **[v1.0.0](https://github.com/philippsyrov/Teyvat-Virtuoso/releases/tag/v1.0.0)** ships as a **macOS arm64** `.dmg`: open it and drag Teyvat Virtuoso into Applications.

<p align="center">
  <img src="assets/screenshots/import.png" alt="Import Score screen with track selection and mapping settings" width="70%">
</p>

Grant **Accessibility** under **System Settings → Privacy & Security → Accessibility** when macOS asks. Keyboard playback depends on it.

### Build from source

```zsh
git clone https://github.com/philippsyrov/Teyvat-Virtuoso.git
cd Teyvat-Virtuoso
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
open 'build/Teyvat Virtuoso.app'
```

The build script produces a self-contained app under `build/`. The running app does not need Python or third-party Swift packages.

## Docs

| Doc | Covers |
| --- | --- |
| [docs/Genshin_Instrument_Key_Mappings.md](docs/Genshin_Instrument_Key_Mappings.md) | The 21-key, three-row lyre layout, with worked key examples |
| [docs/MIDI_Candidate_Preflight.md](docs/MIDI_Candidate_Preflight.md) | Whether a MIDI source will survive the 21-key reduction |
| [docs/PRIVATE_SCORES.md](docs/PRIVATE_SCORES.md) | Where private MIDI belongs, copyright, and what the app saves locally |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## License

MIT, see [LICENSE](LICENSE).

Teyvat Virtuoso is an unofficial fan tool, not affiliated with or endorsed by HoYoverse. Automated input may be restricted by a game's or platform's terms; you decide where and how to use it. The workflow is inspired by [sabihoshi/GenshinLyreMidiPlayer](https://github.com/sabihoshi/GenshinLyreMidiPlayer) (MIT); Teyvat Virtuoso is an independent native macOS app with its own engine and UI.

Built by [Philipp Syrov](https://github.com/philippsyrov).
