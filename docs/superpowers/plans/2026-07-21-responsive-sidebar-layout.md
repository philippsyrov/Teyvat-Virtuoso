# Responsive Sidebar Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the visible sidebar divider and make every macOS page expand and wrap cleanly at the available content width.

**Architecture:** Keep the AppKit navigation structure and add a small scroll-view layout helper that keeps its flipped stack document equal to the clip-view width. Replace page-specific fixed widths with content-column constraints, so descriptions and cards wrap while actions retain their intrinsic size.

**Tech Stack:** Swift 5, AppKit, Python `unittest`, existing shell app build.

## Global Constraints

- Preserve MIDI conversion, playback, community downloads, attribution, and saved-library behavior.
- Keep the 205-point source-list sidebar and 780-point minimum app width.
- Do not package remote community score data.
- Add comments for every non-obvious layout or resize decision.
- Verify with `python3 -m unittest tests/test_play_score.py`, `./scripts/build_app.sh`, and `git diff --check`.

---

### Task 1: Lock the responsive layout contract

**Files:**
- Modify: `tests/test_play_score.py`
- Modify: `player/GenshinLyrePlayerApp.swift`

**Interfaces:**
- Consumes: the existing native sidebar and `FlippedStackView` document pages.
- Produces: source contracts for divider-free navigation and width-tracking page documents.

- [ ] **Step 1: Write the failing test**

Add this test beside `test_scroll_document_uses_intrinsic_content_height`:

```python
def test_sidebar_pages_have_no_visible_divider_or_fixed_content_width(self):
    root = Path(__file__).parents[1]
    source = (root / "player" / "GenshinLyrePlayerApp.swift").read_text()
    self.assertIn("splitView.dividerStyle = .none", source)
    self.assertIn("final class ResponsivePageScrollView", source)
    self.assertIn("documentView.frame.size.width = contentView.bounds.width", source)
    self.assertNotIn("stack.frame = NSRect(x: 0, y: 0, width: 680, height: 0)", source)
```

- [ ] **Step 2: Verify RED**

Run `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_sidebar_pages_have_no_visible_divider_or_fixed_content_width`.

Expected: fail because the split view uses `.thin` and the page stack has a fixed 680-point width.

- [ ] **Step 3: Write the minimal implementation**

Add this class after `FlippedStackView`:

```swift
final class ResponsivePageScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let documentView else { return }
        documentView.frame.size.width = contentView.bounds.width
        documentView.frame.size.height = documentView.fittingSize.height
    }
}
```

Change the navigation shell to `splitView.dividerStyle = .none`. In `makePageScroll`, create `ResponsivePageScrollView()` and initialise the stack with width `0`; the layout override assigns the live clip-view width.

- [ ] **Step 4: Verify GREEN**

Run the focused contract command from Step 2. Expected: one passing test.

- [ ] **Step 5: Commit**

Run `git add player/GenshinLyrePlayerApp.swift tests/test_play_score.py` followed by `git commit -m "fix: make sidebar pages responsive"`.

---

### Task 2: Remove page-level clipping constraints

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: `ResponsivePageScrollView` from Task 1.
- Produces: responsive text columns, score cards, selectors, and import drop area.

- [ ] **Step 1: Write the failing test**

Extend the Task 1 test with:

```python
self.assertNotIn("card.widthAnchor.constraint(equalToConstant: 620)", source)
self.assertNotIn("songPicker.widthAnchor.constraint(equalToConstant: 500)", source)
self.assertNotIn("communitySearchField.widthAnchor.constraint(equalToConstant: 420)", source)
self.assertIn("widthAnchor.constraint(equalTo: contentContainer.widthAnchor", source)
```

- [ ] **Step 2: Verify RED**

Run the focused contract command from Task 1 Step 2. Expected: fail on fixed card, picker, and search widths.

- [ ] **Step 3: Write the minimal implementation**

Create a helper that applies a maximum readable width without forcing a fixed page width:

```swift
private func constrainToPageColumn(_ view: NSView, maximumWidth: CGFloat = 760) {
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
    view.widthAnchor.constraint(equalTo: contentContainer.widthAnchor, constant: -60).isActive = true
}
```

Apply it to the song picker, community search field, community cards, MIDI drop view, and multiline labels. Give title/detail stacks low horizontal compression resistance; give action stacks required horizontal compression resistance.

- [ ] **Step 4: Verify GREEN**

Run `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_sidebar_pages_have_no_visible_divider_or_fixed_content_width` and `python3 -m unittest tests/test_play_score.py`. Expected: focused test and full suite pass.

- [ ] **Step 5: Commit**

Run `git add player/GenshinLyrePlayerApp.swift tests/test_play_score.py` followed by `git commit -m "fix: prevent page content clipping"`.

---

### Task 3: Build, inspect, and install the macOS test app

**Files:**
- Modify only files required by failed verification.

**Interfaces:**
- Consumes: the responsive AppKit layout from Tasks 1 and 2.
- Produces: a signature-verified `Teyvat Virtuoso.app` installed on the Desktop.

- [ ] **Step 1: Run complete verification**

Run `python3 -m unittest tests/test_play_score.py`, `./scripts/build_app.sh`, and `git diff --check`.

Expected: 19 tests pass, the app bundle builds, and no whitespace errors occur.

- [ ] **Step 2: Visually inspect the built app**

Open `build/Teyvat Virtuoso.app`, resize to its minimum width, and check all three destinations in dark mode. Confirm no visible sidebar divider, wrapping text, fitting controls, and persistent Stop footer.

- [ ] **Step 3: Install with rollback**

Move the existing `/Users/philippsyrov/Desktop/Teyvat Virtuoso.app` to a temporary sibling backup, copy the verified build with `ditto`, verify its signature and `community-catalog.json`, then remove the backup only after all checks pass. Restore the backup if any check fails.

- [ ] **Step 4: Commit verification corrections only if needed**

Run `git add player/GenshinLyrePlayerApp.swift tests/test_play_score.py` followed by `git commit -m "fix: polish responsive sidebar layout"`.

---

### Task 4: Remove the title-bar rule and align community actions

**Files:**
- Modify: `player/GenshinLyrePlayerApp.swift`
- Modify: `tests/test_play_score.py`

**Interfaces:**
- Consumes: the responsive community card layout from Task 2.
- Produces: a divider-free title bar and one stable trailing action rail per community card.

- [ ] **Step 1: Write the failing test**

Extend the responsive-layout source contract with:

```python
self.assertIn("window.titlebarSeparatorStyle = .none", source)
self.assertIn("action.widthAnchor.constraint(equalToConstant: 92)", source)
self.assertIn("source.widthAnchor.constraint(equalToConstant: 140)", source)
self.assertIn("title.lineBreakMode = .byTruncatingTail", source)
self.assertIn("details.lineBreakMode = .byTruncatingTail", source)
```

- [ ] **Step 2: Verify RED**

Run `python3 -m unittest tests.test_play_score.ValidateScoreTests.test_sidebar_pages_remove_the_divider_and_track_the_available_width`.

Expected: fail because the title bar still draws its separator and card actions use only intrinsic widths.

- [ ] **Step 3: Write the minimal implementation**

Set `window.titlebarSeparatorStyle = .none` after setting the window title. In each community card, constrain `Open Source` to 140 points and `Play` or `Download` to 92 points. Set both title and credit labels to one line with `.byTruncatingTail`, give the text stack low horizontal compression resistance, and keep the action stack at required resistance so it remains pinned at the trailing edge.

- [ ] **Step 4: Verify GREEN**

Run the focused contract command from Step 2, then `python3 -m unittest tests/test_play_score.py` and `./scripts/build_app.sh`.

Expected: the full suite passes and the native app builds.

- [ ] **Step 5: Visually inspect and install**

Launch the build, check that Community Collection has no bright title-bar rule and aligned action rails, then replace the Desktop app with the signed build using the Task 3 rollback sequence.
