# Full Sky Music Catalogue and Sheet Import Design

## Goal

Let people discover every arrangement named in Sky Music's public legacy catalogue, while keeping all arrangement note data remote until they explicitly choose **Download**. Let people also open a downloaded Sky Music JSON `.txt` sheet directly in Teyvat Virtuoso.

## Scope and source boundary

The app will ship a metadata-only catalogue generated from Sky Music's public `librarySongsList.json`: stable safe ID, display title, remote filename, and the public source-library URL. It will not ship `songNotes`, original `.txt` payloads, MIDI files, audio, or an offline score archive.

The Community Collection continues to fetch exactly one arrangement only after the person presses **Download**, validates it, converts it to normal `ImportedScoreEvent` values, and caches only that converted result in Application Support. Every full-catalogue row displays the existing generic Sky Music attribution and **Open Source** action. The existing curated entries keep their researched duration and arranger metadata; legacy-index-only rows show no invented duration or arranger.

## Catalogue presentation

The Community Collection search field filters the combined catalogue. Favourites stay at the top. The initial display avoids creating thousands of AppKit cards at launch: it shows a bounded first page and a clear filtered-result count; typing searches all metadata. A lightweight **Load more** control reveals additional matching rows in fixed-size batches. Every revealed row retains the same fixed trailing action rail: source, heart, and Download/Play/Stop.

## Direct Sky Music JSON import

Rename the import page's visible entry point from MIDI-only wording to **Import Score** while retaining MIDI behaviour. The file picker and drag target accept `.mid`, `.midi`, `.txt`, and `.json`.

For a JSON/text file, decode the established Sky Music one-song array wrapper. Reuse `CommunitySourceSong.makeScore()` for strict key and timing validation; do not attempt to parse arbitrary JSON or visual HTML pages. The summary names the loaded Sky Music score and its event count. Preview uses the existing playback and focus countdown, and **Save to My Library** stores only converted events plus a user-owned library record, never the source file.

If the selected `.txt`/`.json` is not this exact format, leave the prior imported score intact and show an explanation that the app needs a Sky Music exported sheet, rather than silently producing a broken one-key score.

## Tests and verification

Tests cover decoding a direct local Sky Music sheet, rejecting invalid JSON/text without overwriting prior state, full-catalogue metadata containing no note payload, safe identities, and UI source contracts for the expanded import file types plus bounded community rendering. The existing conversion, cache, MIDI, favourite, and app-build tests remain green.

Before commit, run `python3 -m unittest tests/test_play_score.py` and `./scripts/build_app.sh`.

## Out of scope

- Downloading every arrangement automatically or bundling any score payload.
- Guessing missing song durations, arrangers, pitches, or parsing visual web sheets.
- In-app audio preview, Windows support, accounts, playlists, or cloud sync.
