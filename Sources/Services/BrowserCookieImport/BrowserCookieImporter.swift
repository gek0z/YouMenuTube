import Foundation
import OSLog

private let log = Logger(subsystem: "app.youmenutube", category: "cookie-import")

enum BrowserCookieError: LocalizedError {
    case tccDenied
    case keychainDenied(Browser)
    case storeMissing(URL)
    case storeRead(String)
    case noStore(Browser)
    case notSignedIn(Browser, reason: String)

    var errorDescription: String? {
        switch self {
        case .tccDenied:
            return
                "Safari's cookies live inside a protected container. Grant YouMenuTube Full Disk Access in System Settings → Privacy & Security, then try again."
        case .keychainDenied(let b):
            return
                "Couldn't read \(b.displayName)'s cookie-encryption key from the Keychain. If you clicked Deny on the prompt, remove the 'Always Allow' entry for YouMenuTube in Keychain Access, then try again."
        case .storeMissing(let url):
            return "No cookie store found at \(url.path(percentEncoded: false))."
        case .storeRead(let msg):
            return "Failed to read the cookie store: \(msg)"
        case .noStore(let b):
            return "No \(b.displayName) cookie store found on this machine."
        case .notSignedIn(let b, _):
            return
                "\(b.displayName) isn't signed in to YouTube. Open youtube.com in \(b.displayName), sign in, then try again."
        }
    }
}

/// Reads `youtube.com` cookies out of a browser's on-disk cookie store and
/// returns them as `[HTTPCookie]`. Same filter and validation story as the
/// old `YouTubeService.captureCookiesFromSharedStore`: must include at
/// least one of the session markers (SAPISID / SID / LOGIN_INFO …) or
/// InnerTube will reject the session.
///
/// This path is the replacement for the WKWebView sign-in sheet and solves
/// issue #8: the user signs in *in their own browser* (where passkeys and
/// password managers all work natively) and then hands the session to us.
enum BrowserCookieImporter {
    static let youtubeDomainSuffix = "youtube.com"

    /// Session markers that must be present for InnerTube to accept the
    /// cookie blob. Mirrors the set in
    /// `YouTubeService.captureCookiesFromSharedStore`.
    static let requiredSessionMarkers: Set<String> = [
        "SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID",
        "SID", "__Secure-3PSID", "__Secure-1PSID",
        "LOGIN_INFO",
    ]

    static func importYouTubeCookies(from browser: Browser) async throws -> [HTTPCookie] {
        // Cookie-store reads are disk I/O and (for Chromium) Keychain I/O,
        // which can block on authorisation prompts. Run off the main actor.
        try await Task.detached(priority: .userInitiated) {
            try Self.readCookies(for: browser)
        }.value
    }

    private static func readCookies(for browser: Browser) throws -> [HTTPCookie] {
        let all: [HTTPCookie]
        switch browser.format {
        case .safari:
            let home = FileManager.default.homeDirectoryForCurrentUser
            guard let url = browser.safariCookieStore(home: home) else {
                throw BrowserCookieError.noStore(browser)
            }
            all = try SafariBinaryCookies.read(at: url, domainSuffix: youtubeDomainSuffix)
            log.notice("safari: read \(all.count) youtube.com cookies")
        case .chromium:
            let stores = BrowserDetector.chromiumCookieStores(for: browser)
            guard let store = stores.first else { throw BrowserCookieError.noStore(browser) }
            all = try ChromiumCookies.read(browser: browser, storeURL: store, domainSuffix: youtubeDomainSuffix)
            log.notice("\(browser.rawValue): read \(all.count) cookies from \(store.path(percentEncoded: false))")
        case .firefox:
            let stores = BrowserDetector.firefoxCookieStores()
            guard let store = stores.first else { throw BrowserCookieError.noStore(browser) }
            all = try FirefoxCookies.read(at: store, domainSuffix: youtubeDomainSuffix)
            log.notice("firefox: read \(all.count) cookies from \(store.path(percentEncoded: false))")
        }

        // Keep the youtube.com-only filter (load-bearing per SECURITY.md:
        // mixing .google.com / accounts.google.com cookies triggers
        // InnerTube loggedOut=true).
        let youtubeOnly = all.filter { $0.domain.hasSuffix(youtubeDomainSuffix) }

        let names = Set(youtubeOnly.map(\.name))
        let markersFound = names.intersection(requiredSessionMarkers)
        guard !markersFound.isEmpty else {
            throw BrowserCookieError.notSignedIn(
                browser,
                reason:
                    "no session markers among \(youtubeOnly.count) youtube.com cookies (need at least one of \(requiredSessionMarkers.sorted().joined(separator: ", ")))"
            )
        }

        return youtubeOnly
    }
}
