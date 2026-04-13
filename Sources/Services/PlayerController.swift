import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PlayerController {
    var videoId: String?
    var title: String?

    func play(videoId: String, title: String) {
        self.videoId = videoId
        self.title = title
        NSApp.activate(ignoringOtherApps: true)
        Self.closeMenuBarPopover()
    }

    func stop() {
        videoId = nil
        title = nil
    }

    /// SwiftUI's MenuBarExtra (`.window` style) doesn't expose a public way to
    /// dismiss the popover, so we find the underlying status-bar window by its
    /// runtime class name and order it out.
    private static func closeMenuBarPopover() {
        for window in NSApp.windows {
            let cls = String(describing: type(of: window))
            if cls.contains("StatusBar") || cls.contains("MenuBarExtra") {
                window.orderOut(nil)
            }
        }
    }
}
