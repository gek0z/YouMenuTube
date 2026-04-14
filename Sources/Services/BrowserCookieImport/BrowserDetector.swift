import Foundation

/// Finds which browsers the user actually has a cookie store for on this
/// machine, so the import UI only offers real choices. We don't use
/// `NSWorkspace.urlForApplication(withBundleIdentifier:)` — an app being
/// installed doesn't mean it has ever been run, and without a cookie store
/// there's nothing to import. Presence of the data directory is the real
/// signal.
enum BrowserDetector {
    static func installed() -> [Browser] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return Browser.allCases.filter { browser in
            switch browser.format {
            case .safari:
                // We *can't* stat the Safari container without Full Disk Access
                // (the stat itself is gated by TCC on macOS 13+). Always list
                // Safari and let the reader surface the TCC error if FDA hasn't
                // been granted — that's a clearer UX than silently hiding it.
                return true
            case .chromium:
                guard let root = browser.userDataRoot(home: home) else { return false }
                return fm.fileExists(atPath: root.path(percentEncoded: false))
            case .firefox:
                guard let root = browser.userDataRoot(home: home) else { return false }
                return fm.fileExists(atPath: root.path(percentEncoded: false))
            }
        }
    }

    /// All directories under a Chromium user-data root that contain a
    /// `Cookies` file, ordered most-recently-modified first. Each directory
    /// corresponds to a browser profile (`Default`, `Profile 1`, `Profile 2`,
    /// …). The most recently modified one is almost always the one the user
    /// was last active in.
    static func chromiumCookieStores(for browser: Browser) -> [URL] {
        guard browser.format == .chromium else { return [] }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        guard let root = browser.userDataRoot(home: home),
            let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }

        let candidates: [(URL, Date)] = children.compactMap { profileDir in
            let cookies = profileDir.appending(path: "Cookies", directoryHint: .notDirectory)
            guard fm.fileExists(atPath: cookies.path(percentEncoded: false)) else { return nil }
            let mtime =
                (try? cookies.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return (cookies, mtime)
        }
        return candidates.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Firefox stores profiles under a root directory with randomised names
    /// (e.g. `abcdef.default-release`). Return every profile that has a
    /// `cookies.sqlite`, most-recently-modified first.
    static func firefoxCookieStores() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        guard let root = Browser.firefox.userDataRoot(home: home) else { return [] }
        let profilesDir = root.appending(path: "Profiles", directoryHint: .isDirectory)
        guard
            let children = try? fm.contentsOfDirectory(
                at: profilesDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            )
        else { return [] }

        let candidates: [(URL, Date)] = children.compactMap { profileDir in
            let cookies = profileDir.appending(path: "cookies.sqlite", directoryHint: .notDirectory)
            guard fm.fileExists(atPath: cookies.path(percentEncoded: false)) else { return nil }
            let mtime =
                (try? cookies.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return (cookies, mtime)
        }
        return candidates.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
