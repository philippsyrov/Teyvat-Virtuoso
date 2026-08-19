import AppKit
import Foundation

final class SidebarTestDelegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 1 }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedSidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: "Community Collection")
    }
}

func shellExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data(("FAIL: \(message)\n").utf8))
        exit(1)
    }
}

@main
struct AppShellLayoutTests {
    static func main() {
        let navigation = NSView()
        let content = NSView()
        let shell = AppShellView(
            navigationView: navigation,
            contentView: content,
            sidebarWidth: 205,
            titlebarClearance: 52
        )
        shell.frame = NSRect(x: 0, y: 0, width: 940, height: 720)
        shell.layoutSubtreeIfNeeded()

        shellExpect(content.frame == NSRect(x: 205, y: 0, width: 735, height: 720), "music content must use the complete window height to the right of the sidebar")
        shellExpect(navigation.frame == NSRect(x: 0, y: 0, width: 205, height: 668), "navigation must reach the bottom edge while leaving only native titlebar clearance; got \(navigation.frame)")
        shellExpect(shell.subviews.count == 2, "the app shell must contain no footer or status surface")

        let selection = RoundedSidebarRowView.selectionRect(in: NSRect(x: 0, y: 0, width: 205, height: 36))
        shellExpect(selection == NSRect(x: 10, y: 2, width: 185, height: 32), "sidebar selection must keep equal rounded space on its left and right edges")
        let row = RoundedSidebarRowView()
        shellExpect(row.selectionHighlightStyle == .none, "sidebar rows must disable AppKit's full-width source-list highlight before drawing the inset pill")

        let sidebarDelegate = SidebarTestDelegate()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 205, height: 200))
        let table = NSTableView(frame: scroll.contentView.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Navigation"))
        column.width = 190
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.dataSource = sidebarDelegate
        table.delegate = sidebarDelegate
        scroll.documentView = table
        table.reloadData()
        scroll.layoutSubtreeIfNeeded()
        table.layoutSubtreeIfNeeded()
        guard let visibleRow = table.rowView(atRow: 0, makeIfNecessary: true) as? RoundedSidebarRowView else {
            FileHandle.standardError.write(Data("FAIL: expected a rounded sidebar row\n".utf8))
            exit(1)
        }
        shellExpect(visibleRow.bounds.width > scroll.contentView.bounds.width, "the source-list row should reproduce AppKit's wider document width")
        shellExpect(visibleRow.selectionRectForDrawing().maxX == 195, "the selected pill must use the 205-point visible sidebar width and retain a 10-point right margin")
        print("AppShellLayoutTests passed")
    }
}
