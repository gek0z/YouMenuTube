import Foundation

enum WindowID {
    static let player = "player"
    static let signIn = "youtube-signin"
}

enum UserAgent {
    /// Safari UA string used to spoof WKWebView when talking to YouTube /
    /// Google. Google sign-in is blocked for the default WKWebView UA, and
    /// the IFrame player emits error 152-4 without it.
    static let safari =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
}

enum BuiltInPlaylist {
    static let watchLater = "VLWL"
    static let likedVideos = "VLLL"

    /// Stored pin ids predating the YouTubeKit switch lacked the "VL"
    /// prefix. Both legacy and current shapes must be recognised when
    /// filtering the "my playlists" list so the built-ins don't render
    /// twice.
    static let allIds: Set<String> = [watchLater, likedVideos, "WL", "LL"]

    /// Upgrades a pre-VL pin id to its current form, or nil if nothing
    /// needs migrating.
    static func migrated(_ id: String) -> String? {
        switch id {
        case "WL": return watchLater
        case "LL": return likedVideos
        default: return nil
        }
    }
}
