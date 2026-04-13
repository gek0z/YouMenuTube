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
    }

    func stop() {
        videoId = nil
        title = nil
    }
}
