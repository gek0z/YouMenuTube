import AppKit
import OSLog
import SwiftUI

private let importLog = Logger(subsystem: "app.youmenutube", category: "import-session")

/// Replacement for the old `YouTubeSignInWindow`. The user signs in to
/// YouTube *in their own browser* — where passkeys and password managers
/// all work natively — and we import their `youtube.com` cookies from that
/// browser's on-disk cookie store.
///
/// See `BrowserCookieImporter` for the mechanics, and issue #8 for why the
/// old embedded-WKWebView flow had to go.
struct ImportSessionWindow: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(DockPresence.self) private var dock
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var browsers: [Browser] = []
    @State private var selected: Browser?
    @State private var status: Status = .idle

    enum Status {
        case idle
        case importing
        case success(Int)
        case failure(BrowserCookieError)

        var isWorking: Bool { if case .importing = self { true } else { false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            browserPicker
            headsUpBanner
            statusRow
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 480, height: 460)
        .onAppear {
            dock.present(WindowID.importSession)
            browsers = BrowserDetector.installed()
            selected = browsers.first
            bringToFront()
        }
        .onDisappear { dock.dismiss(WindowID.importSession) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Import your YouTube session")
                .font(.title2).bold()
            Text(
                "Sign in to YouTube in your browser — passkeys, password managers, and all. Then pick that browser below and we'll copy the session into YouMenuTube."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var browserPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browser").font(.headline)
            if browsers.isEmpty {
                Text("No supported browser found on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                // We use a `Menu` rather than `Picker(.menu)` because the
                // closed-state of `Picker(.menu)` flattens to NSPopUpButton,
                // which ignores SwiftUI frame modifiers on vector images
                // and renders the brand SVGs at their native viewBox size.
                // With `Menu`, the closed-state label is pure SwiftUI and
                // honours our 16×16 frame; the dropdown rows go through
                // NSMenu, where pre-sizing the `NSImage` keeps them tidy.
                Menu {
                    ForEach(browsers) { b in
                        Button {
                            selected = b
                        } label: {
                            Label {
                                Text(b.displayName)
                            } icon: {
                                browserIcon(b)
                            }
                        }
                    }
                } label: {
                    if let b = selected {
                        HStack(spacing: 8) {
                            browserIcon(b)
                            Text(b.displayName)
                        }
                    } else {
                        Text("Select a browser")
                    }
                }
                .menuStyle(.borderlessButton)
                .disabled(status.isWorking)
            }
        }
    }

    /// Warns the user about the one-time OS prompt their selected browser
    /// will trigger, so the "why is this app asking for my login password?"
    /// moment doesn't come out of nowhere. Firefox has no prompt → no banner.
    @ViewBuilder
    private var headsUpBanner: some View {
        if let browser = selected {
            switch browser.format {
            case .chromium:
                Banner(
                    icon: "lock.shield",
                    text:
                        "macOS will ask for your login password once — that's the standard Keychain prompt that lets YouMenuTube read \(browser.displayName)'s cookie-encryption key. Click **Always Allow** to skip it on later imports. Touch ID may appear on Macs that support it."
                )
            case .safari:
                Banner(
                    icon: "externaldrive.badge.exclamationmark",
                    text:
                        "Safari's cookies live in a protected container. Import will fail the first time unless YouMenuTube has **Full Disk Access** in System Settings → Privacy & Security."
                )
            case .firefox:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .importing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Importing…").foregroundStyle(.secondary)
            }
        case .success(let count):
            Label("Imported \(count) cookies. You're signed in.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let error):
            errorPanel(error)
        }
    }

    @ViewBuilder
    private func errorPanel(_ error: BrowserCookieError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.errorDescription ?? "Import failed.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                switch error {
                case .tccDenied:
                    Button("Open Full Disk Access settings") {
                        if let url = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }
                case .notSignedIn(let browser, _), .noStore(let browser):
                    Button("Sign in to YouTube in \(browser.displayName)") {
                        openYouTubeSignIn(in: browser)
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { dismissWindow(id: WindowID.importSession) }
            Button {
                Task { await runImport() }
            } label: {
                Text("Import").frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil || status.isWorking)
        }
    }

    private func runImport() async {
        guard let browser = selected else { return }
        yt.clearLastError()
        status = .importing
        do {
            let cookies = try await BrowserCookieImporter.importYouTubeCookies(from: browser)
            if yt.ingest(cookies: cookies) {
                status = .success(cookies.count)
                importLog.notice("imported \(cookies.count) cookies from \(browser.rawValue)")
                try? await Task.sleep(for: .milliseconds(500))
                dismissWindow(id: WindowID.importSession)
            } else {
                status = .failure(
                    .notSignedIn(browser, reason: "cookies had no valid session markers"))
            }
        } catch let err as BrowserCookieError {
            importLog.error("import failed for \(browser.rawValue): \(err.localizedDescription, privacy: .public)")
            status = .failure(err)
        } catch {
            importLog.error("unexpected import error: \(error.localizedDescription, privacy: .public)")
            status = .failure(.storeRead(error.localizedDescription))
        }
    }

    private func openYouTubeSignIn(in browser: Browser) {
        guard let url = URL(string: "https://www.youtube.com/signin") else { return }
        let config = NSWorkspace.OpenConfiguration()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Loads the browser's brand icon as a pre-sized `NSImage`. AppKit's
    /// NSMenu sizes item images from the `NSImage.size` property and
    /// ignores SwiftUI frame modifiers, so vector SVGs without an
    /// intrinsic size render at their native viewBox (huge). Copying the
    /// cached named image and setting `size` fixes the dropdown rows.
    private func browserIcon(_ browser: Browser) -> Image {
        guard let original = NSImage(named: browser.iconAsset),
            let sized = original.copy() as? NSImage
        else { return Image(systemName: "globe") }
        sized.size = NSSize(width: 16, height: 16)
        return Image(nsImage: sized)
    }

    private func bringToFront() {
        // `NSApp.activate(ignoringOtherApps:)` was softened in macOS 14 — it
        // only activates if the caller was recently user-facing, which a
        // MenuBarExtra popover is not once it closes. `activate()` (no arg)
        // is the replacement and works reliably for LSUIElement apps.
        NSApp.activate()
        // The NSWindow usually isn't in `NSApp.windows` yet when `onAppear`
        // fires on first open. Poll a few times instead of assuming one
        // runloop is enough — fixes the "Sign in button did nothing"
        // symptom when the host app is an LSUIElement + MenuBarExtra.
        Task { @MainActor in
            for _ in 0..<10 {
                if let w = NSApp.windows.first(where: { $0.title == "Import YouTube session" }) {
                    w.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

private struct Banner: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .font(.title3)
            Text(.init(text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
}
