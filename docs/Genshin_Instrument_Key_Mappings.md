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

## Best Mac setup

1. Use Genshin through GeForce NOW, not iPhone Mirroring.
2. Keep the game focused while a score plays.
3. Store tunes as separate JSON files in a `songs/` folder.
4. Use a small local Mac score player that sends key-down events together, waits until the next timestamp, then releases them together.

That fourth step is how we get real multi-key chords and repeatable recorded tunes. A native Swift score player is the cleanest option: no extra macro app, a song library, dry-run mode, and one command per tune. It needs macOS Accessibility permission before it can send keyboard events.

## Important boundary

Only use it for attended instrument performance. Game rules can treat unattended automation or macros differently, so keep a visible game window, start each tune yourself, and do not use it for gameplay or farming.
