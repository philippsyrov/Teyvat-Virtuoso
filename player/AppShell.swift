import AppKit

// Keep window chrome confined to the sidebar while the music pane uses the full height.
final class AppShellView: NSView {
    init(
        navigationView: NSView,
        contentView: NSView,
        statusView: NSView,
        sidebarWidth: CGFloat,
        titlebarClearance: CGFloat,
        statusHeight: CGFloat
    ) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for view in [navigationView, contentView, statusView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            navigationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            navigationView.widthAnchor.constraint(equalToConstant: sidebarWidth),
            navigationView.topAnchor.constraint(equalTo: topAnchor, constant: titlebarClearance),
            navigationView.bottomAnchor.constraint(equalTo: statusView.topAnchor),

            statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusView.widthAnchor.constraint(equalToConstant: sidebarWidth),
            statusView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: statusHeight),

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
    static func selectionRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: 10, dy: 2)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let path = NSBezierPath(roundedRect: Self.selectionRect(in: bounds), xRadius: 9, yRadius: 9)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
    }
}
