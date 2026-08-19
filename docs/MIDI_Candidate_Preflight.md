# MIDI candidate preflight

This is a source-file check, not a promise that every song will sound right on a 21-key white-note lyre. A score only moves forward when its lead, accompaniment, and timing survive separately.

| MIDI | Best shared shift | Natural-note fit | Call |
| --- | ---: | ---: | --- |
| `He's a Pirate (3)` | -5 | 98.7% | Excellent next full conversion: 2 parts and hundreds of real source chords. |
| `We Found Love` | 0 | 100.0% | Strong candidate: one dense source part with 144 genuine chord onsets. |
| `Davy Jones` | -5 | 97.8% | Faithful short cue candidate; 39 seconds, 4 role tracks. |
| `Stronger (vocal)` | -1 | 96.9% | Sparse 65-note vocal line only, so not an Aloha-style performance source. |
| `Caribbean Blue` | 0 | 73.8% | Do not force it onto lyre: it is substantially chromatic. |
| `Bohemian Rhapsody` | +2 | 79.4% | Do not make a full lyre reduction: it is very chromatic and 16:47 long. |

## Useful ideas retained from sabihoshi/GenshinLyreMidiPlayer

- Keep source tracks separate, then select roles deliberately rather than flattening everything into one stream.
- Apply one shared transposition to an arrangement, so melody and accompaniment remain in the same key.
- Keep original MIDI onset timing; only merge notes that truly start together into an actual chord.
- Reject, or manually isolate, tracks with too many chromatic notes instead of silently mangling them.
- Keep playback offline and focused: the destination game window must be in front before a performance begins.

The repository tool is `scripts/preflight_midi.py`. It prints the duration, source tracks, playable-note percentage, best shared shift, and actual chord density before a MIDI is imported into the app.
