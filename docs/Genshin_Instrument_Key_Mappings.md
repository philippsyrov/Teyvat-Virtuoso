# Genshin Instrument Key Mappings

Last checked: 20 July 2026, using Genshin Impact through GeForce NOW on Mac.

## Harp and piano

These instruments use three diatonic rows. Read each row left to right as `do re mi fa so la ti`.

| Octave / row | Keys | Notes |
| --- | --- | --- |
| High / treble | `Q W E R T Y U` | do re mi fa so la ti |
| Middle | `A S D F G H J` | do re mi fa so la ti |
| Low / bass | `Z X C V B N M` | do re mi fa so la ti |

Worked example: a middle C-major arpeggio is `A D G D`.

## Guitar / ukulele

The two note rows are the same as the middle and low rows above. The top row plays full built-in chords.

| Control | Keys | Left-to-right mapping |
| --- | --- | --- |
| Chords | `Q W E R T Y U` | C, Dm, Em, F, G, Am, G7 |
| Upper notes | `A S D F G H J` | do re mi fa so la ti |
| Lower notes | `Z X C V B N M` | do re mi fa so la ti |

Worked example: a C chord followed by an upper C is `Q`, then `A`.

## Reliable score format

Represent each event as a time plus one or more keys. One key is a melody note; several keys at the same time are a chord.

```json
[
  { "at_ms": 0, "keys": ["q"] },
  { "at_ms": 350, "keys": ["a"] },
  { "at_ms": 700, "keys": ["d", "g"] }
]
```

## Using Teyvat Virtuoso on Mac

1. Use Genshin through GeForce NOW, not iPhone Mirroring.
2. Import a MIDI or compatible Sky Music sheet into Teyvat Virtuoso.
3. Preview the reduction, then keep the game focused while the saved performance plays.
4. Use **Stop** on the active card whenever you need to interrupt playback.

Teyvat Virtuoso sends simultaneous key-down events for real multi-key chords and follows the source event timeline. macOS Accessibility permission is required before it can send keyboard events to the focused game window.

## Important boundary

Only use it for attended instrument performance. Game rules can treat unattended automation or macros differently, so keep a visible game window, start each tune yourself, and do not use it for gameplay or farming.
