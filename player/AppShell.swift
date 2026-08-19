import AppKit

enum LibraryCardLayout {
    static let expandedSpeedEditorInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    static let expandedSpeedEditorBottomSpacing: CGFloat = 12
}

// Keep window chrome confined to the sidebar while the music pane uses the full height.
final class AppShellView: NSView {
    init(
        navigationView: NSView,
        contentView: NSView,
        sidebarWidth: CGFloat,
        titlebarClearance: CGFloat
    ) {
        super.init(frame: .zero)

        for view in [navigationView, contentView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            navigationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            navigationView.widthAnchor.constraint(equalToConstant: sidebarWidth),
            navigationView.topAnchor.constraint(equalTo: topAnchor, constant: titlebarClearance),
            navigationView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sidebarWidth),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class RoundedSidebarTableView: NSTableView {
    override var style: NSTableView.Style {
        get { .plain }
        set { }
    }

    override var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
        get { .none }
        set { }
    }
}

// Draw a soft selection pill without letting its right edge hit the content transition.
final class RoundedSidebarRowView: NSTableRowView {
    override var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
        get { .none }
        set { }
    }

    static func selectionRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: 10, dy: 2)
    }

    static func selectionRect(rowBounds: NSRect, clipWidth: CGFloat) -> NSRect {
        var clippedBounds = rowBounds
        clippedBounds.size.width = min(rowBounds.width, clipWidth)
        return selectionRect(in: clippedBounds)
    }

    func selectionRectForDrawing() -> NSRect {
        let clipWidth = enclosingScrollView?.contentView.bounds.width ?? visibleRect.width
        return Self.selectionRect(rowBounds: bounds, clipWidth: clipWidth)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: selectionRectForDrawing(), xRadius: 9, yRadius: 9)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
    }
}
