import Foundation
import OSLog
import Observation
import YouTubeKit

private let log = Logger(subsystem: "app.youmenutube", category: "yt-service")

/// Single auth + API surface for the app. Uses YouTubeKit (InnerTube) for
/// everything, signed in via cookies imported from the user's own browser
/// (Safari / Chrome / Firefox / etc — see `BrowserCookieImporter`). No
/// Google Cloud project, no API key, no OAuth — just a YouTube login
/// handed to us by the browser the user already uses.
///
/// Trade-off: InnerTube is YouTube's *internal* API. It can break and is
/// against ToS strictly speaking. Use for personal projects.
@Observable
@MainActor
final class YouTubeService {
    private(set) var isSignedIn: Bool = false
    var lastError: String?

    /// Video IDs known to be in the user's Watch Later. Populated lazily on
    /// sign-in (first page only — covers the most-recent items) and updated
    /// optimistically on add/remove. Reads are local; only the toggle action
    /// itself hits the network.
    private(set) var watchLaterIds: Set<String> = []

    @ObservationIgnored let model: YouTubeModel
    @ObservationIgnored private var watchLaterRefreshTask: Task<Void, Never>?
    private let cookiesKey = "youtube.cookies.v1"

    init() {
        self.model = YouTubeModel()
        if let data = Keychain.get(cookiesKey), let header = String(data: data, encoding: .utf8) {
            apply(cookies: header)
        }
    }

    // MARK: - Auth (cookies)

    private func apply(cookies: String) {
        model.cookies = cookies
        model.alwaysUseCookies = !cookies.isEmpty
        isSignedIn = !cookies.isEmpty
        if isSignedIn {
            refreshWatchLaterIds()
        } else {
            watchLaterIds = []
        }
    }

    func signOut() {
        Keychain.delete(cookiesKey)
        model.cookies = ""
        model.alwaysUseCookies = false
        isSignedIn = false
        watchLaterRefreshTask?.cancel()
        watchLaterIds = []
    }

    /// Called before showing the import UI so the previous run's error text
    /// doesn't stick around in Settings → Diagnostic while the user's
    /// re-import attempt is in flight.
    func clearLastError() {
        lastError = nil
    }

    /// Called when any authenticated endpoint reports `isDisconnected` —
    /// YouTube rejected our cookies despite them being present locally.
    /// Wipes the stale session so every tab (Home included) reflects the
    /// signed-out state consistently, instead of Home silently falling
    /// through to the public feed while other tabs surface an error.
    private func handleDisconnected() {
        log.notice("server reported disconnected session — wiping local cookies")
        lastError = YTServiceError.disconnected.errorDescription
        signOut()
    }

    /// Persists a batch of `HTTPCookie`s (already filtered to `youtube.com`
    /// and validated by the caller) as a single Cookie header. Used by
    /// `BrowserCookieImporter` after reading the user's browser store.
    ///
    /// The filter + session-marker validation live on the importer side
    /// now so the UI can surface a precise "this browser isn't signed in
    /// to YouTube" error before we even get here. This method trusts its
    /// input and does the last-mile persistence only.
    @discardableResult
    func ingest(cookies: [HTTPCookie]) -> Bool {
        let relevant = cookies.filter { $0.domain.hasSuffix("youtube.com") }
        guard !relevant.isEmpty else { return false }

        // A browser stores cookies keyed by (name, domain, path) and sends
        // only the ones whose path prefixes the request path — one value
        // per name, with the longest matching path winning. If we concatenate
        // every row from the store we can end up with e.g. three
        // `VISITOR_INFO1_LIVE=…` values in the header (paths `/`, `/embed`,
        // `/m`), which InnerTube answers with `loggedOut=true` because a
        // real browser would never have sent duplicates. Pick the one that
        // would apply to `/youtubei/v1/…`: longest path that's a prefix of
        // the request path, tie-broken by latest expiration.
        let requestPath = "/youtubei/v1/browse"
        let unique = Self.dedupedForRequest(relevant, requestPath: requestPath)

        let byDomain = Dictionary(grouping: unique, by: { $0.domain })
            .mapValues { $0.map(\.name).sorted().joined(separator: ",") }
        let diagnostic = byDomain.keys.sorted().map { "\($0): \(byDomain[$0] ?? "")" }.joined(separator: " | ")
        log.notice(
            "ingest: \(relevant.count)→\(unique.count) after dedup, cookies by domain → \(diagnostic, privacy: .public)"
        )

        let header = unique.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        Keychain.set(Data(header.utf8), for: cookiesKey)
        apply(cookies: header)
        lastError = nil
        log.notice("ingest: persisted \(unique.count) cookies, header length=\(header.count)")
        return true
    }

    private static func dedupedForRequest(_ cookies: [HTTPCookie], requestPath: String) -> [HTTPCookie] {
        // Stable ordering: best candidate per name lands first, weaker
        // candidates after it; then a single forward pass keeps the first.
        let sorted = cookies.sorted { a, b in
            let aMatches = requestPath.hasPrefix(a.path)
            let bMatches = requestPath.hasPrefix(b.path)
            if aMatches != bMatches { return aMatches }
            if a.path.count != b.path.count { return a.path.count > b.path.count }
            let ax = a.expiresDate ?? .distantFuture
            let bx = b.expiresDate ?? .distantFuture
            return ax > bx
        }
        var seen: Set<String> = []
        return sorted.filter { seen.insert($0.name).inserted }
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
        if resp.isDisconnected {
            handleDisconnected()
            throw YTServiceError.disconnected
        }
        return resp.results.map(Self.entry(from:)).uniqued(by: \.id)
    }

    // MARK: - My playlists

    func myPlaylists() async throws -> [PlaylistEntry] {
        try ensureSignedIn()
        let resp = try await AccountPlaylistsResponse.sendThrowingRequest(
            youtubeModel: model, data: [:], useCookies: true
        )
        if resp.isDisconnected {
            handleDisconnected()
            throw YTServiceError.disconnected
        }
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

    // MARK: - Watch Later

    func isInWatchLater(_ videoId: String) -> Bool {
        watchLaterIds.contains(videoId)
    }

    func addToWatchLater(videoId: String) async throws {
        try ensureSignedIn()
        watchLaterIds.insert(videoId)
        do {
            let resp = try await AddVideoToPlaylistResponse.sendThrowingRequest(
                youtubeModel: model,
                data: [.browseId: "WL", .movingVideoId: videoId]
            )
            if resp.isDisconnected {
                handleDisconnected()
                throw YTServiceError.disconnected
            }
            guard resp.success else { throw YTServiceError.actionFailed }
        } catch {
            watchLaterIds.remove(videoId)
            throw error
        }
    }

    func removeFromWatchLater(videoId: String) async throws {
        try ensureSignedIn()
        watchLaterIds.remove(videoId)
        do {
            let resp = try await RemoveVideoByIdFromPlaylistResponse.sendThrowingRequest(
                youtubeModel: model,
                data: [.browseId: "WL", .movingVideoId: videoId]
            )
            if resp.isDisconnected {
                handleDisconnected()
                throw YTServiceError.disconnected
            }
            guard resp.success else { throw YTServiceError.actionFailed }
        } catch {
            watchLaterIds.insert(videoId)
            throw error
        }
    }

    /// Reload the Watch Later membership cache. Only fetches the first page —
    /// far-back items won't show as "saved" until the user toggles them, but
    /// the optimistic local cache keeps recent toggles accurate.
    func refreshWatchLaterIds() {
        watchLaterRefreshTask?.cancel()
        watchLaterRefreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let entries = try await self.playlistItems(playlistId: BuiltInPlaylist.watchLater)
                if Task.isCancelled { return }
                self.watchLaterIds = Set(entries.map(\.id))
            } catch {
                log.error("watch-later cache refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
            viewCount: v.viewCount,
            duration: v.timeLength,
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
    case actionFailed
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to YouTube first."
        case .disconnected:
            return
                "YouTube rejected the session. Sign out and re-import from your browser — make sure the browser is signed in to youtube.com, not just accounts.google.com."
        case .actionFailed:
            return "YouTube rejected the action."
        }
    }
}
