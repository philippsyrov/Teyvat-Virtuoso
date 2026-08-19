import AppKit

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

// Draw a soft selection pill without letting its right edge hit the content transition.
final class RoundedSidebarRowView: NSTableRowView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectionHighlightStyle = .none
    }

    required init?(coder: NSCoder) { nil }

    static func selectionRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: 10, dy: 2)
    }

    func selectionRectForDrawing() -> NSRect {
        Self.selectionRect(in: visibleRect)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: selectionRectForDrawing(), xRadius: 9, yRadius: 9)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
    }
}
