import AppKit
import Foundation

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
        let status = NSView()
        let shell = AppShellView(
            navigationView: navigation,
            contentView: content,
            statusView: status,
            sidebarWidth: 205,
            titlebarClearance: 52,
            statusHeight: 52
        )
        shell.frame = NSRect(x: 0, y: 0, width: 940, height: 720)
        shell.layoutSubtreeIfNeeded()

        shellExpect(content.frame == NSRect(x: 205, y: 0, width: 735, height: 720), "music content must use the complete window height to the right of the sidebar")
        shellExpect(status.frame == NSRect(x: 0, y: 0, width: 205, height: 52), "status must occupy only the bottom of the sidebar")
        shellExpect(navigation.frame == NSRect(x: 0, y: 52, width: 205, height: 616), "navigation must leave titlebar clearance without creating a full-width top or bottom bar; got \(navigation.frame)")

        let selection = RoundedSidebarRowView.selectionRect(in: NSRect(x: 0, y: 0, width: 205, height: 36))
        shellExpect(selection == NSRect(x: 10, y: 2, width: 185, height: 32), "sidebar selection must keep equal rounded space on its left and right edges")
        print("AppShellLayoutTests passed")
    }
}
