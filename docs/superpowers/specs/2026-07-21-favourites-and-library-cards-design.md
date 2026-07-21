# Favourites, source discovery, and library-card design

## Goal

Keep community arrangements external and attributed, while making both collections feel like one coherent player. A person can discover the complete Sky Music library, explicitly download an individual arrangement, favourite any visible score, and stop its playback from that row.

## Community discovery and attribution

- The Community Collection intro gains a compact `Browse all Sky Music sheets` action that opens `https://sky-music.github.io/` in the person's default browser.
- Each existing community card retains its own `Open Source` link and download-on-click behaviour. The app continues to bundle only metadata; it never bundles community note data.
- The browser action is discovery only. It does not scrape, import, or silently download material.

## Shared card layout

- My Library changes from a picker plus detached controls to vertically stacked cards using the Community Collection card geometry.
- Each card has a one-line title, one-line subtitle, and a fixed trailing action rail. Long text tail-truncates before the rail.
- Every card has a heart in the secondary-action position. Community cards show `Open Source`, heart, and `Play`/`Download`; saved-library cards show heart and `Play`.
- Favourites appear before ordinary cards while preserving their prior order within each group.

## Favourite persistence

- A small Application Support favourites manifest owns favourite identities for every card class: bundled public scores, locally imported scores, and community catalog entries.
- Existing local favourite state migrates into that shared manifest on first load, so current favourites are not lost.
- Toggling a heart persists immediately, refreshes only the affected page, and gives a concise status message. A failed write leaves the visible order unchanged.

## Playback controls

- Playback exposes one UI state: idle or active score identity.
- The active card's primary button reads `Stop`; all other ready cards remain `Play`. A not-yet-cached community card continues to read `Download`.
- Pressing `Stop` cancels playback through the existing controller, returns the active row to `Play`, and retains the global footer Stop as a secondary safety control.
- Starting another score transfers the active state to that score without allowing two playback jobs at once.

## Verification

- Unit tests cover shared favourite persistence, stable favourite-first ordering, and migration of existing local favourites.
- Source-contract tests assert the external browse action, card rails on both pages, and active-row Stop label.
- The existing MIDI, community conversion, full app build, signing, and live UI checks remain required.

## Project naming

- After the verified app is installed, rename the visible local repository folder and its GitHub repository from `TeyvatVirtuoso` to `Teyvat Virtuoso`.
- Preserve the existing git history, remote relationship, worktree metadata, and application bundle name while updating only the human-facing repository name.
