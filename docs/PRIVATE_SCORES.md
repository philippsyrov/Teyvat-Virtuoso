# Private score workflow

Put a downloaded or purchased MIDI in `scores/private/`.

Run the preflight before converting anything:

```zsh
python3 scripts/preflight_midi.py 'scores/private/your-song.mid'
```

The report does three useful checks:

1. It finds one global transposition with the highest natural-note fit.
2. It lists each MIDI track separately, including its range and true simultaneous chord count.
3. It gives a conservative verdict. “Strong candidate” means “worth arranging,” not “automatically faithful.”

For a good result, keep the lead melody recognisable first. Then choose bass and accompaniment tracks that fit the other two rows. Preserve source timing and merge only genuine simultaneous notes; do not add fake arpeggios just because a score looks thin.

Never add a private MIDI or a generated arrangement to Git unless you have clear redistribution rights.

When you choose **Save to Library**, Teyvat Virtuoso stores only generated key-event JSON under your macOS Application Support folder. The original MIDI is never copied, modified, or added to the repository.
