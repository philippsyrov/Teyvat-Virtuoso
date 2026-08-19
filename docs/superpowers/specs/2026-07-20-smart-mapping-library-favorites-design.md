# Smart Mapping and Personal Library Design

## Goal

Improve imported MIDI reductions without changing proven scores, and make the saved-song picker usable as a small personal performance library.

## Scope

This change adds a key-aware missing-note policy, persistent favourites, and a safe clear-library action. Aloha ʻOe remains the only bundled performance. Existing keyboard playback, timing, chord emission, MIDI privacy, and the Aloha score remain unchanged.

## Smart key-aware mapping

`Smart — key-aware` becomes the selected missing-note policy whenever a MIDI is loaded. Strict, Snap down, and Snap up remain available and retain their current behaviour.

The engine analyses only enabled tracks after applying the selected shared transpose. It builds a duration-independent pitch-class histogram from note-on events and compares it with all 24 major and natural-minor key profiles. The highest-scoring profile becomes the detected key; deterministic ordering resolves exact ties.

For a chromatic pitch unavailable on Genshin's natural-note keyboard, the engine evaluates the adjacent natural notes below and above. A candidate receives priority when it belongs to the detected scale. When both or neither candidates qualify, the engine chooses the candidate that best preserves the incoming melodic interval within the same source track. Remaining ties resolve downward for deterministic output. Natural pitches are never changed by this policy.

The import summary displays the detected key for the currently enabled tracks and transpose. Changing track selection or transpose updates the key used when generating the next preview or saved score. The original MIDI is never modified.

## Library model and favourites

The bundled manifest contains only Aloha ʻOe. It is protected from clearing and always appears first.

Locally generated `Song` entries gain an optional `isFavorite` Boolean. Missing values decode as false so existing manifests remain readable. A Favourite/Unfavourite control beside the song selector updates the local manifest atomically. Favourited imported songs display with a heart prefix and sort before non-favourite imported songs; Aloha remains first.

Saving an imported score creates a non-favourite entry. Repeated titles remain separate because generated identifiers and filenames stay unique.

## Clearing imported songs

The window adds `Clear Imported Library…`. It opens a native confirmation alert stating that generated saved arrangements will be removed while original MIDI files and Aloha remain untouched.

On confirmation, the store removes its generated score JSON files and replaces `custom-library.json` with an empty library atomically. The live selector immediately returns to Aloha only. Cancellation performs no writes.

During installation of this feature, the app's existing Application Support directory is moved to a timestamped sibling backup before the fresh app is launched. This one-time installation cleanup is separate from the in-app clear action.

## Permissions and compatibility

The bundle identifier and complete-bundle ad-hoc signing remain unchanged. Library edits require no new macOS permissions. Replacing a local build should retain Accessibility approval; if macOS invalidates it, the existing playback preflight stops and explains how to refresh the permission.

Saved and bundled JSON scores are already-resolved key events. Smart mapping applies only while previewing or saving a newly imported MIDI and never rewrites existing arrangements.

## Error handling

If key detection receives no enabled notes, score generation returns no events through the existing empty-score path. Failed favourite or clear-library writes leave the current in-memory picker unchanged and show a readable status message. File deletion is restricted to generated filenames resolved beneath Teyvat Virtuoso's Application Support score directory.

## Tests

Engine tests cover major and minor key detection, scale-preferred snapping, contour tie-breaking, deterministic ties, natural-note preservation, and regressions for Strict/Down/Up.

Store and app-contract tests cover backward-compatible favourite decoding, persistent favourite updates, sorting, confirmation-backed clearing, Aloha protection, the single bundled manifest entry, and the Smart default. Full verification remains `python3 -m unittest tests/test_play_score.py`, `./scripts/build_app.sh`, `git diff --check`, and code-signature validation.
