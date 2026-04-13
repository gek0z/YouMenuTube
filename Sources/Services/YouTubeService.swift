import Foundation
import OSLog
import Observation
import WebKit
import YouTubeKit

private let log = Logger(subsystem: "app.youmenutube", category: "yt-service")

/// Single auth + API surface for the app. Uses YouTubeKit (InnerTube) for
/// everything, signed in via cookies captured from a WKWebView. No Google
/// Cloud project, no API key, no OAuth — just a YouTube login.
///
/// Trade-off: InnerTube is YouTube's *internal* API. It can break and is
/// against ToS strictly speaking. Use for personal projects.
@Observable
@MainActor
final class YouTubeService {
    private(set) var isSignedIn: Bool = false
    var lastError: String?

    @ObservationIgnored let model: YouTubeModel
    private let cookiesKey = "youtube.cookies.v1"

    init() {
        self.model = YouTubeModel()
        if let data = Keychain.get(cookiesKey), let header = String(data: data, encoding: .utf8) {
            apply(cookies: header)
        }
    }

    // MARK: - Auth (cookies)

    /// A WKWebsiteDataRecord is "ours" if it's hosted under youtube.com or
    /// google.com — those are the only domains our sign-in flow touches,
    /// and wiping them between attempts prevents Google's detection from
    /// latching onto stale visitor cookies.
    private static func isYouTubeOrGoogle(_ record: WKWebsiteDataRecord) -> Bool {
        record.displayName.contains("youtube") || record.displayName.contains("google")
    }

    private func apply(cookies: String) {
        model.cookies = cookies
        model.alwaysUseCookies = !cookies.isEmpty
        isSignedIn = !cookies.isEmpty
    }

    func signOut() {
        Keychain.delete(cookiesKey)
        model.cookies = ""
        model.alwaysUseCookies = false
        isSignedIn = false

        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage,
        ]
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records.filter(Self.isYouTubeOrGoogle)) {}
        }
    }

    /// Reads cookies from the shared WKWebsiteDataStore (where the sign-in
    /// sheet's WKWebView wrote them) and persists them if a usable session
    /// is present. Populates `lastError` with the set of cookie names found
    /// so we can diagnose when InnerTube rejects the session despite cookies
    /// being present.
    @discardableResult
    func captureCookiesFromSharedStore() async -> Bool {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            store.getAllCookies { cont.resume(returning: $0) }
        }
        log.notice("capture: got \(cookies.count) total cookies in shared store")

        // Only send cookies scoped to youtube.com in the InnerTube header. Mixing
        // in .google.com / accounts.google.com cookies (LSID, __Host-1PLSID, OTZ,
        // etc.) would never happen in a real browser request to www.youtube.com,
        // and InnerTube responds with loggedOut=true when it sees them.
        let relevant = cookies.filter { $0.domain.hasSuffix("youtube.com") }

        let byDomain = Dictionary(grouping: relevant, by: { $0.domain })
            .mapValues { $0.map(\.name).sorted().joined(separator: ",") }
        let diagnostic = byDomain.keys.sorted().map { "\($0): \(byDomain[$0] ?? "")" }.joined(separator: " | ")
        log.notice("capture: youtube.com cookies by domain → \(diagnostic, privacy: .public)")

        let sessionMarkers: Set<String> = [
            "SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID",
            "SID", "__Secure-3PSID", "__Secure-1PSID",
            "LOGIN_INFO",
        ]
        let present = Set(relevant.map(\.name)).intersection(sessionMarkers)
        log.notice("capture: session markers present → \(present.sorted().joined(separator: ","), privacy: .public)")

        guard !present.isEmpty else {
            lastError = "No authenticated session cookies on youtube.com. \(diagnostic)"
            log.error("capture: no youtube.com session markers — aborting")
            return false
        }

        let header = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        Keychain.set(Data(header.utf8), for: cookiesKey)
        apply(cookies: header)
        lastError = "Captured \(relevant.count) youtube.com cookies. \(diagnostic)"
        log.notice("capture: persisted \(relevant.count) cookies, header length=\(header.count)")
        return true
    }

    /// Wipes youtube.com / google.com cookies and site data from the shared
    /// WKWebsiteDataStore so a fresh sign-in starts from clean state. Google's
    /// detection can latch onto stale visitor cookies accumulated across failed
    /// attempts, so we clear before opening the sign-in webview.
    func clearWebSignInState() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { cont in
            store.fetchDataRecords(ofTypes: types) { cont.resume(returning: $0) }
        }
        let targets = records.filter(Self.isYouTubeOrGoogle)
        log.notice(
            "clear: wiping \(targets.count) site-data records (\(targets.map(\.displayName).joined(separator: ","), privacy: .public))"
        )
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, for: targets) { cont.resume() }
        }
    }

    // MARK: - Home feed

    /// YouTube's main home recommendations. Works signed-out (returns generic
    /// suggestions) but is much richer with cookies attached.
    func homeFeed() async throws -> [VideoEntry] {
        let resp = try await HomeScreenResponse.sendThrowingRequest(
            youtubeModel: model, data: [:], useCookies: true
        )
        return resp.results.map(Self.entry(from:)).uniqued(by: \.id)
    }

    // MARK: - Subscriptions feed

    func subscriptionsFeed() async throws -> [VideoEntry] {
        try ensureSignedIn()
        let resp = try await AccountSubscriptionsFeedResponse.sendThrowingRequest(
            youtubeModel: model, data: [:], useCookies: true
        )
        if resp.isDisconnected { throw YTServiceError.disconnected }
        return resp.results.map(Self.entry(from:)).uniqued(by: \.id)
    }

    // MARK: - My playlists

    func myPlaylists() async throws -> [PlaylistEntry] {
        try ensureSignedIn()
        let resp = try await AccountPlaylistsResponse.sendThrowingRequest(
            youtubeModel: model, data: [:], useCookies: true
        )
        if resp.isDisconnected { throw YTServiceError.disconnected }
        return resp.results.map(Self.entry(from:)).uniqued(by: \.id)
    }

    // MARK: - Playlist items

    /// Fetch items for any playlist by id ("VLPL…", "VLWL", "VLLL…").
    /// Accepts ids with or without the "VL" prefix.
    func playlistItems(playlistId rawId: String) async throws -> [VideoEntry] {
        let id = rawId.hasPrefix("VL") ? rawId : "VL\(rawId)"
        let resp = try await PlaylistInfosResponse.sendThrowingRequest(
            youtubeModel: model, data: [.browseId: id], useCookies: true
        )
        return resp.results.map(Self.entry(from:)).uniqued(by: \.id)
    }

    // MARK: - Search

    func search(_ query: String) async throws -> [VideoEntry] {
        let resp = try await SearchResponse.sendThrowingRequest(
            youtubeModel: model, data: [.query: query]
        )
        return
            resp.results
            .compactMap { $0 as? YTVideo }
            .map(Self.entry(from:))
            .uniqued(by: \.id)
    }

    // MARK: - Helpers

    private func ensureSignedIn() throws {
        if !isSignedIn { throw YTServiceError.notSignedIn }
    }

    private static func entry(from v: YTVideo) -> VideoEntry {
        let bestThumb = v.thumbnails.max { ($0.width ?? 0) < ($1.width ?? 0) }
        // YouTubeKit decodes shorts via decodeShortFromJSON / decodeShortFromLockupJSON,
        // which leaves channel, timePosted, and timeLength all nil. Regular videos
        // always carry at least one of these.
        let isShort = v.channel == nil && v.timePosted == nil && v.timeLength == nil
        return VideoEntry(
            id: v.videoId,
            title: v.title ?? "(untitled)",
            channelTitle: v.channel?.name,
            timePosted: v.timePosted,
            thumbnailURL: bestThumb?.url,
            isShort: isShort
        )
    }

    private static func entry(from p: YTPlaylist) -> PlaylistEntry {
        let bestThumb = p.thumbnails.max { ($0.width ?? 0) < ($1.width ?? 0) }
        let count = p.videoCount.flatMap { Int($0.filter(\.isNumber)) }
        return PlaylistEntry(
            id: p.playlistId,
            title: p.title ?? "Untitled",
            videoCount: count,
            thumbnailURL: bestThumb?.url
        )
    }
}

enum YTServiceError: LocalizedError {
    case notSignedIn
    case disconnected
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to YouTube first."
        case .disconnected:
            return
                "YouTube rejected the session. Sign out and sign in again — make sure you reach youtube.com logged-in (not just accounts.google.com)."
        }
    }
}
