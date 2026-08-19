# Community Collection and Native Sidebar Design

## Goal

Turn Teyvat Virtuoso's single crowded workbench into a calm native macOS player with three clearly separated jobs: discovering community arrangements, managing personal saved performances, and importing MIDI files.

The redesign must preserve the working MIDI engine, keyboard playback, saved per-song speed, favourites, and Accessibility identity. It must not place copyrighted community arrangements in the public repository or imply that community work belongs to Teyvat Virtuoso.

## Navigation and window structure

The app uses a native source-list sidebar with three destinations:

1. **Community Collection** — browse and cache compatible community arrangements.
2. **My Library** — play and manage bundled public-domain demonstrations plus user-saved performances.
3. **Import MIDI** — analyse, configure, preview, and save a local MIDI reduction.

Only one destination is visible at a time. A persistent footer spans the content area and contains playback status plus an immediate Stop button. The initial window is wider than the current workbench so list rows and MIDI metadata do not collide, while retaining a sensible minimum size.

## Community Collection

The Community Collection reads searchable metadata and arrangement data from the existing Sky Music community endpoint used by Genshin Music Nightly. It is an online, optional feature; My Library and MIDI import continue working offline.

The first release ships a curated catalog manifest containing metadata and remote source identifiers, not copyrighted note data. The curated set includes the compatible arrangements already inspected for note count, duration, chord density, and natural-note range.

Each row displays:

- title;
- duration;
- arranger when the source provides one;
- source collection attribution;
- whether the arrangement is available locally;
- a primary **Download** or **Play** action.

Selecting a song shows its complete credit and a clickable source link. The app labels the section as community work and never describes it as official, bundled, owned, or endorsed content.

Downloaded arrangement data is validated before storage. It must contain supported source keys, non-negative timestamps, and at least one event. The validated result is converted into the app's normal 21-key score schema and cached beneath the app's standard macOS Application Support directory. A small local manifest stores title, credit, source URL, cache filename, and attribution metadata. Network, decoding, validation, and file errors appear without deleting an existing cache.

## My Library

My Library contains only:

- redistributable public-domain examples shipped with the app; and
- performances the user explicitly saves locally.

It does not silently merge remote community entries into the same selector. The selected song displays its subtitle, saved playback speed, and favourite state. The main actions are **Play** and **Favourite**. Destructive or uncommon actions, including clearing imported performances, move into a compact actions menu and retain confirmation.

## Import MIDI

Import MIDI keeps the existing drag-and-drop and file-picker workflow. The screen is reorganised into:

1. an empty-state drop area or loaded-file summary;
2. the enabled-track list;
3. a collapsed **Advanced mapping** disclosure containing transpose, missing-note policy, merge tolerance, and playback speed;
4. primary **Preview** and **Save to My Library** actions.

The existing conversion behavior is unchanged. Saving records the currently selected playback speed automatically; no separate “Set Saved Speed” action appears in the importer.

## Visual direction

The UI uses native AppKit controls and system materials rather than custom decoration. It follows a restrained macOS utility style:

- source-list sidebar with icons and clear selection;
- one large page title and one concise explanation per destination;
- consistent 16-point content spacing and aligned control widths;
- grouped sections with subtle native backgrounds instead of many separator lines;
- accent colour reserved for primary playback/download actions;
- secondary metadata shown smaller and quieter than titles;
- action labels that fit without truncation at the minimum supported window size.

The redesign does not add artwork, gradients, custom themes, animations, or unrelated settings.

## Data boundaries and attribution

The public repository may contain community catalog metadata, source links, attribution, conversion code, and tests. It must not contain copyrighted community note-event files unless explicit redistribution permission is documented.

Every cached community song retains its source credit. If an arranger name is absent, the app displays **Community arrangement · Sky Music library** rather than inventing an author. The app also adds a Credits/About section explaining that community arrangements remain the work of their respective arrangers and linking to Genshin Music Nightly and its open-source repository.

## Downloadable macOS releases

The repository adds a GitHub Actions release workflow triggered by version tags matching `v*`. The workflow runs the complete test suite, builds the native application with the repository build script, packages `Teyvat Virtuoso.app` as a Finder-safe ZIP, generates a SHA-256 checksum, and attaches both files to the matching GitHub Release.

The first release remains ad-hoc signed because the project does not currently have Apple Developer ID and notarisation credentials. The README must state this plainly and provide the normal macOS first-open instructions. The workflow is structured so Developer ID signing and notarisation can be added later through GitHub secrets without changing the downloadable asset names.

## Test contract

Automated tests cover:

- parsing and validating community arrangement responses;
- conversion of 15-key community events into safe 21-key score events while preserving timing and simultaneous chords;
- rejection of unknown keys, negative timestamps, empty arrangements, and path traversal;
- cache manifests retaining title, arranger, source link, and local filename;
- strict separation between Community Collection and My Library;
- the saved-speed behavior continuing to apply per personal song;
- UI source contracts for the three sidebar destinations, Advanced mapping disclosure, visible per-song attribution, and persistent Stop control;
- the existing MIDI engine and application build.
- the release workflow producing a ZIP whose app has the stable bundle identifier.

Manual verification covers sidebar switching, online download, offline cached playback, source-link opening, MIDI drag-and-drop, saving to My Library, favourite state, saved speed, Stop behavior, resizing, and dark-mode readability.

## Out of scope

- Bundling the entire remote community library.
- Editing or publishing community arrangements.
- User accounts, ratings, playlists, or cloud synchronisation.
- Replacing the MIDI reduction algorithm.
- Downloading or redistributing original commercial MIDI files.
- Apple Developer ID purchasing, signing, or notarisation credentials.
