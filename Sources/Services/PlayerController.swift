import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PlayerController {
    var videoId: String?
    var title: String?
    /// Incremented every time the user asks to play something — observed by the
    /// App scene to call `openWindow(id:)`, which must be invoked from a View.
    var openRequestCounter: Int = 0

    func play(videoId: String, title: String) {
        self.videoId = videoId
        self.title = title
        openRequestCounter &+= 1
        NSApp.activate(ignoringOtherApps: true)
    }

    func stop() {
        videoId = nil
        title = nil
    }
}
