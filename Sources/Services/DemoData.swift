import Foundation

/// Curated, hardcoded fixtures served by `YouTubeService` when the app
/// is launched in demo mode (`-demo-mode` / `YMT_DEMO_MODE=1`). Populated
/// with real, famous YouTube video IDs so thumbnails render from
/// `i.ytimg.com` and clicking a row still plays the real video in the
/// embedded player — no network call needed to produce the row itself.
///
/// To change the look of the screenshots, edit the arrays below.
enum DemoData {

    // MARK: - Videos

    /// Builds a `VideoEntry` using `https://i.ytimg.com/vi/<id>/hqdefault.jpg`
    /// for the thumbnail — which reliably exists for any real video ID.
    private static func video(
        _ id: String,
        _ title: String,
        channel: String,
        time: String,
        views: String,
        duration: String
    ) -> VideoEntry {
        VideoEntry(
            id: id,
            title: title,
            channelTitle: channel,
            timePosted: time,
            viewCount: views,
            duration: duration,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            isShort: false
        )
    }

    /// What the Home tab shows in demo mode. Classic memes / viral videos —
    /// thumbnails all come from `i.ytimg.com` for these real IDs. Order is
    /// curated so the most-recently-added entries land above the fold of
    /// the 420×560 popover (~6 rows visible without scrolling).
    static let homeFeed: [VideoEntry] = [
        video(
            "tzD9OxAHtzU", "skibidi toilet",
            channel: "DaFuq!?Boom!", time: "3 years ago",
            views: "320M views", duration: "0:11"),
        video(
            "VQKMoT-6XSg", "iPhone 1 - Steve Jobs MacWorld keynote in 2007 - Full Presentation",
            channel: "Protectstar Inc.", time: "15 years ago",
            views: "14M views", duration: "1:20:16"),
        video(
            "92fLApYaCGI", "Michael Jordan \"The Last Shot\" – #NBATogetherLive Classic Game",
            channel: "NBA", time: "6 years ago",
            views: "32M views", duration: "2:33"),
        video(
            "qRv7G7WpOoU", "SNOWBOARDING WITH THE NYPD",
            channel: "CaseyNeistat", time: "9 years ago",
            views: "8.4M views", duration: "3:51"),
        video(
            "XnygT6ANLzQ", "Skrilla - Doot Doot (6 7) (Official Music Video)",
            channel: "Skrilla", time: "1 year ago",
            views: "16M views", duration: "2:17"),
        video(
            "dQw4w9WgXcQ", "Rick Astley - Never Gonna Give You Up (Official Music Video)",
            channel: "Rick Astley", time: "15 years ago",
            views: "1.6B views", duration: "3:33"),
        video(
            "txqiwrbYGrs", "David After Dentist",
            channel: "booba1234", time: "16 years ago",
            views: "143M views", duration: "1:58"),
        video(
            "dMH0bHeiRNg", "Evolution of Dance - By Judson Laipply",
            channel: "judsonlaipply", time: "19 years ago",
            views: "300M views", duration: "6:00"),
        video(
            "HEXWRTEbj1I", "Haddaway - What Is Love (Official Video)",
            channel: "Haddaway", time: "16 years ago",
            views: "480M views", duration: "4:30"),
        video(
            "9bZkp7q19f0", "PSY - GANGNAM STYLE (강남스타일) M/V",
            channel: "officialpsy", time: "13 years ago",
            views: "5.3B views", duration: "4:13"),
        video(
            "jNQXAC9IVRw", "Me at the zoo",
            channel: "jawed", time: "20 years ago",
            views: "370M views", duration: "0:19"),
        video(
            "_OBlgSz8sSM", "Charlie bit my finger - again !",
            channel: "HDCYT", time: "17 years ago",
            views: "900M views", duration: "0:56"),
        video(
            "jofNR_WkoCE", "Ylvis - The Fox (What Does The Fox Say?) [Official music video HD]",
            channel: "TVNorge", time: "12 years ago",
            views: "1.1B views", duration: "3:45"),
        video(
            "kffacxfA7G4", "Justin Bieber - Baby (Official Music Video) ft. Ludacris",
            channel: "Justin Bieber", time: "16 years ago",
            views: "3.0B views", duration: "3:36"),
    ]

    /// What the Subscriptions tab shows in demo mode.
    static let subscriptionsFeed: [VideoEntry] = [
        video(
            "tzD9OxAHtzU", "skibidi toilet",
            channel: "DaFuq!?Boom!", time: "2 days ago",
            views: "4.1M views", duration: "0:11"),
        video(
            "XnygT6ANLzQ", "Skrilla - Doot Doot (6 7) (Official Music Video)",
            channel: "Skrilla", time: "4 days ago",
            views: "2.8M views", duration: "2:17"),
        video(
            "txqiwrbYGrs", "David After Dentist",
            channel: "booba1234", time: "1 week ago",
            views: "620K views", duration: "1:58"),
        video(
            "dMH0bHeiRNg", "Evolution of Dance - By Judson Laipply",
            channel: "judsonlaipply", time: "1 week ago",
            views: "1.3M views", duration: "6:00"),
        video(
            "HEXWRTEbj1I", "Haddaway - What Is Love (Official Video)",
            channel: "Haddaway", time: "2 weeks ago",
            views: "3.0M views", duration: "4:30"),
        video(
            "_OBlgSz8sSM", "Charlie bit my finger - again !",
            channel: "HDCYT", time: "3 weeks ago",
            views: "2.7M views", duration: "0:56"),
    ]

    // MARK: - Playlists

    /// What the Playlists tab shows in demo mode (on top of the built-in
    /// Watch Later / Liked Videos synthetic rows, which the view inserts
    /// itself). The "VL" prefix is what YouTubeKit returns for real ids.
    static let playlists: [PlaylistEntry] = [
        playlist("VLPLdemo_rickrolls", "Certified Rickrolls", count: 17, firstVideo: "dQw4w9WgXcQ"),
        playlist("VLPLdemo_memes", "Internet Hall of Fame", count: 42, firstVideo: "jNQXAC9IVRw"),
        playlist("VLPLdemo_brainrot", "Brain Rot 2025", count: 31, firstVideo: "tzD9OxAHtzU"),
        playlist("VLPLdemo_dancefloor", "Unskippable Dancefloor", count: 19, firstVideo: "9bZkp7q19f0"),
        playlist("VLPLdemo_guilty", "Guilty Pleasures", count: 35, firstVideo: "kffacxfA7G4"),
    ]

    private static func playlist(_ id: String, _ title: String, count: Int, firstVideo: String) -> PlaylistEntry {
        PlaylistEntry(
            id: id,
            title: title,
            videoCount: count,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(firstVideo)/hqdefault.jpg")
        )
    }

    /// What `playlistItems(playlistId:)` returns in demo mode. The special
    /// cases are Watch Later (VLWL) and Liked Videos (VLLL); every other
    /// id falls back to a shuffled generic mix so every playlist opens to
    /// something interesting.
    static func items(for rawId: String) -> [VideoEntry] {
        let id = rawId.hasPrefix("VL") ? rawId : "VL\(rawId)"
        // Indices map into `homeFeed`:
        //   0 Skibidi Toilet     1 Steve Jobs iPhone     2 MJ Last Shot
        //   3 Snowboarding NYPD  4 Doot Doot (6 7)       5 Rick Astley
        //   6 David After Dentist 7 Evolution of Dance   8 What Is Love
        //   9 Gangnam Style      10 Me at the zoo        11 Charlie bit my finger
        //   12 The Fox           13 Baby
        switch id {
        case "VLWL":
            return [homeFeed[5], homeFeed[11], homeFeed[0], homeFeed[4]]
        case "VLLL":
            return [homeFeed[10], homeFeed[7], homeFeed[6], homeFeed[9], homeFeed[12]]
        case "VLPLdemo_rickrolls":
            return [homeFeed[5], homeFeed[12], homeFeed[8]]
        case "VLPLdemo_memes":
            return [homeFeed[10], homeFeed[11], homeFeed[6], homeFeed[7], homeFeed[12]]
        case "VLPLdemo_brainrot":
            return [homeFeed[0], homeFeed[4], homeFeed[9], homeFeed[11]]
        case "VLPLdemo_dancefloor":
            return [homeFeed[9], homeFeed[7], homeFeed[8], homeFeed[4]]
        case "VLPLdemo_guilty":
            return [homeFeed[13], homeFeed[5], homeFeed[9], homeFeed[12]]
        default:
            return Array(homeFeed.prefix(6))
        }
    }

    /// Seed set for the "is this in my Watch Later?" cache — drives the
    /// clock badge state on Home rows on first launch.
    static let watchLaterIds: Set<String> = ["dQw4w9WgXcQ", "tzD9OxAHtzU", "XnygT6ANLzQ", "dMH0bHeiRNg"]

    // MARK: - Search

    /// Very cheap substring match so typing in the search box in demo mode
    /// actually narrows a visible list. Falls back to everything when the
    /// query is empty (shouldn't happen — the view short-circuits empty
    /// queries — but harmless).
    static func search(_ query: String) -> [VideoEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return homeFeed }
        let all = homeFeed + subscriptionsFeed
        let matches = all.filter {
            $0.title.lowercased().contains(q) || ($0.channelTitle ?? "").lowercased().contains(q)
        }
        return matches.isEmpty ? Array(homeFeed.shuffled().prefix(6)) : matches.uniqued(by: \.id)
    }

    // MARK: - Activation

    /// Checks process launch arguments and environment for the demo flag.
    /// Kept here so the check lives alongside the fixtures it gates.
    static var isEnabled: Bool {
        let info = ProcessInfo.processInfo
        if info.arguments.contains("-demo-mode") || info.arguments.contains("--demo") { return true }
        if let v = info.environment["YMT_DEMO_MODE"], v == "1" || v.lowercased() == "true" { return true }
        return false
    }
}
