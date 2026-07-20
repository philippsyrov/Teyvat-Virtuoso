# Teyvat Virtuoso

A tiny native macOS player for Genshin's three-row lyre keyboard. It sends the mapped Mac keys to the focused game window, preserves a prepared score's timing, and presses chord notes together.

This is deliberately not a “throw any MIDI at it and hope” app. The game lyre has only 21 natural notes:

```text
High:   Q W E R T Y U
Middle: A S D F G H J
Low:    Z X C V B N M
```

## What it does

- Plays prepared JSON scores with original rests and simultaneous chords.
- Gives five seconds to focus Genshin / GeForce NOW before playback.
- Offers 90%, 100%, and 110% timing without changing note order.
- Stops cleanly before the next event.
- Includes a MIDI preflight script so unsuitable files are rejected before they become bad arrangements.

## Build and run

```zsh
cd '/Users/philippsyrov/Desktop/CS Projects/TeyvatVirtuoso'
python3 -m pip install -r scripts/requirements.txt
python3 -m unittest tests/test_play_score.py
./scripts/build_app.sh
open 'build/Teyvat Virtuoso.app'
```

Open the lyre in Genshin, click the game during the five-second countdown, then leave it focused. The app sends real key-down and key-up events, so it can play saved chords rather than mouse-clicking one note at a time.

## MIDI preflight

```zsh
python3 scripts/preflight_midi.py '/path/to/song.mid'
```

The preflight prints the duration, named tracks, best single transposition, white-note fit, and real chord density. A high global fit is only the starting point: the lead melody must also remain recognisable and the accompaniment needs to fit the three rows.

## How a MIDI becomes a lyre score

1. Read MIDI tracks and keep their original timestamped note onsets.
2. Select the meaningful roles — usually melody, accompaniment, and bass — instead of flattening every track.
3. Choose one shared key shift for the whole arrangement.
4. Map natural notes into the high, middle, and low rows.
5. Preserve equal-time notes as chords; near-equal notes may be merged only when the source clearly intended one chord.
6. Reject overly chromatic arrangements rather than silently changing their identity.

## Score rights

The repository contains only public-domain sample arrangements. Keep downloaded, purchased, and copyrighted MIDI files under `scores/private/`; that folder is ignored by Git. Do not publish an arrangement unless you have permission to redistribute both the source and your derivative score.

## Credits

The MIDI workflow was informed by [sabihoshi/GenshinLyreMidiPlayer](https://github.com/sabihoshi/GenshinLyreMidiPlayer), an MIT-licensed Windows project. This macOS implementation is independent; it keeps the useful ideas of track selection, shared transposition, source timing, and near-note merging without using the Windows UI or input stack.
