import Foundation

/// Browsers we know how to pull youtube.com cookies from.
///
/// Three on-disk formats, nine browser variants:
///   - Safari binarycookies                → Safari
///   - Chromium SQLite + Keychain AES key  → Chrome, Edge, Arc, Brave, Vivaldi, Opera
///   - Firefox SQLite (plain)              → Firefox, Zen
enum Browser: String, CaseIterable, Identifiable {
    case safari, chrome, edge, arc, brave, vivaldi, opera, helium, firefox, zen

    var id: String { rawValue }

    enum Format { case safari, chromium, firefox }

    var format: Format {
        switch self {
        case .safari: .safari
        case .firefox, .zen: .firefox
        case .chrome, .edge, .arc, .brave, .vivaldi, .opera, .helium: .chromium
        }
    }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .arc: "Arc"
        case .brave: "Brave"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .helium: "Helium"
        case .firefox: "Firefox"
        case .zen: "Zen"
        }
    }

    /// Bundle id used to target `NSWorkspace.open(url, configuration:)` at
    /// this specific browser (for the "Sign in to YouTube in <Browser>"
    /// shortcut when the user isn't signed in yet).
    var bundleId: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .edge: "com.microsoft.edgemac"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .opera: "com.operasoftware.Opera"
        case .helium: "net.imput.helium"
        case .firefox: "org.mozilla.firefox"
        case .zen: "app.zen-browser.zen"
        }
    }

    /// Asset-catalog image name for the browser picker row. Sourced from
    /// each vendor's official wordmark/logo and namespaced under the
    /// `Browsers` group in `Assets.xcassets`.
    var iconAsset: String {
        "Browsers/\(rawValue)"
    }

    /// Root directory that contains this browser's user data. `nil` for
    /// Safari because its path is singular (not profile-structured).
    func userDataRoot(home: URL) -> URL? {
        let appSupport = home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        switch self {
        case .safari: return nil
        case .chrome: return appSupport.appending(path: "Google/Chrome", directoryHint: .isDirectory)
        case .edge: return appSupport.appending(path: "Microsoft Edge", directoryHint: .isDirectory)
        case .arc: return appSupport.appending(path: "Arc/User Data", directoryHint: .isDirectory)
        case .brave: return appSupport.appending(path: "BraveSoftware/Brave-Browser", directoryHint: .isDirectory)
        case .vivaldi: return appSupport.appending(path: "Vivaldi", directoryHint: .isDirectory)
        case .opera: return appSupport.appending(path: "com.operasoftware.Opera", directoryHint: .isDirectory)
        case .helium: return appSupport.appending(path: "net.imput.helium", directoryHint: .isDirectory)
        case .firefox: return appSupport.appending(path: "Firefox", directoryHint: .isDirectory)
        case .zen: return appSupport.appending(path: "zen", directoryHint: .isDirectory)
        }
    }

    /// Safari-only single cookie store. Reading it requires Full Disk Access
    /// because `com.apple.Safari` is a sandboxed container owned by another app.
    func safariCookieStore(home: URL) -> URL? {
        guard self == .safari else { return nil }
        return home.appending(
            path: "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
            directoryHint: .notDirectory
        )
    }

    /// Keychain service name used to look up the AES key Chromium uses to
    /// encrypt cookie values. These are set by each browser at install time
    /// as a `kSecClassGenericPassword` entry in the login keychain.
    ///
    /// Most Chromium forks use "<Brand> Safe Storage" with account "<Brand>",
    /// but Helium uses "Helium Storage Key" / "Helium", so this is handled
    /// per-case rather than synthesised from `displayName`.
    var chromiumSafeStorageService: String? {
        switch self {
        case .chrome: "Chrome Safe Storage"
        case .edge: "Microsoft Edge Safe Storage"
        case .arc: "Arc Safe Storage"
        case .brave: "Brave Safe Storage"
        case .vivaldi: "Vivaldi Safe Storage"
        case .opera: "Opera Safe Storage"
        case .helium: "Helium Storage Key"
        default: nil
        }
    }

    /// Keychain account name paired with the service above. Most Chromium
    /// forks use the browser's own short name.
    var chromiumSafeStorageAccount: String? {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Microsoft Edge"
        case .arc: "Arc"
        case .brave: "Brave"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .helium: "Helium"
        default: nil
        }
    }
}
