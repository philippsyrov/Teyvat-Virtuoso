# Teyvat Virtuoso workflow

This is a native macOS Swift app plus small Python MIDI analysis tools.

- Keep the player small: source timing, three-row lyre mapping, simultaneous chords, and a clear stop button.
- Do not silently turn chromatic MIDI into random white notes. Preflight a MIDI, choose tracks deliberately, and document any unavoidable reduction.
- Do not commit copyrighted MIDI files or arrangements without explicit redistribution permission. Put them in `scores/private/`, which is ignored.
- Comments should explain each non-obvious line or musical conversion decision.
- Before committing, run `python3 -m unittest tests/test_play_score.py` and `./scripts/build_app.sh`.
