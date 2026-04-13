import Foundation

/// Minimal display model for a video row anywhere in the app.
struct VideoEntry: Identifiable, Hashable, Sendable {
    let id: String  // YouTube video ID
    let title: String
    let channelTitle: String?
    let timePosted: String?  // YouTube's relative-time string e.g. "3 days ago"
    let viewCount: String?  // Pre-formatted e.g. "1.2M views"
    let duration: String?  // Pre-formatted e.g. "12:34" or "1:02:05"; nil for live/shorts
    let thumbnailURL: URL?
    let isShort: Bool
}

/// Minimal display model for a playlist row.
struct PlaylistEntry: Identifiable, Hashable, Sendable {
    let id: String  // YouTubeKit's "VL…"-prefixed playlist id
    let title: String
    let videoCount: Int?
    let thumbnailURL: URL?
}
