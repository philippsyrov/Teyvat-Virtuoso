# Visual-sheet score trial design

## Goal

Add two playable trial arrangements without representing visual notation as a source-timed MIDI file.

## Howl's Moving Castle

- Add the timed Sky Music library arrangement as metadata only.
- Download and convert it only when a person clicks its Community Collection card.
- Retain the exact source link and credit; do not bundle its note payload.

## Fur Elise

- Add a visual-sheet conversion marked as `Visual-sheet timing`.
- Convert its supported lyre notes into evenly spaced app score events at a 100% default rate.
- Reuse the existing playback timing selector for slower or faster performance.
- Reject notes outside the app's 21-key lyre map rather than silently changing their pitch.

## Verification

- Add parser tests for single notes, simultaneous chord groups, unsupported notes, and deterministic timing.
- Test the complete app build and confirm both cards retain their source labels.
