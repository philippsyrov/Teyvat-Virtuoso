# Responsive Sidebar Layout Polish Design

## Goal

Remove the heavy divider between the navigation sidebar and page content, and let every page use the available content width without clipping text or leaving an artificial fixed-width boundary.

## Layout changes

The `NSSplitView` keeps the existing 205-point sidebar and its normal resize behavior, but uses no visible divider. The content pane remains constrained by the existing minimum width so the app cannot shrink until its controls become unusable.

Each scroll page stops using a fixed 680-point document width. Its document stack instead tracks the scroll view's content width minus its existing horizontal page insets. Vertical content height continues to use fitting size so the import controls do not stretch.

All page descriptions become width-aware wrapping labels. Existing fields, cards, and MIDI drop targets replace fixed widths with leading/trailing constraints inside the responsive page column. Rows keep their buttons visible while their title and attribution text wrap before being truncated.

## Boundaries

This does not alter MIDI conversion, playback timing, stored songs, community download behavior, or the source and attribution model. It only changes AppKit layout constraints and adds source-level regression checks for divider-free, responsive content sizing.

## Verification

The test suite will assert the hidden split divider and responsive page-document constraints. Manual verification will resize all three destinations down to the app minimum width in dark mode, confirming that sidebar selection, page text, community credits, controls, and the persistent Stop footer remain visible.
