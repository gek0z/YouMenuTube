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
            statusRow
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 480, height: 440)
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
                Picker("Browser", selection: $selected) {
                    ForEach(browsers) { b in
                        Label(b.displayName, systemImage: b.symbol).tag(Optional(b))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(status.isWorking)
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

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            NSApp.windows
                .first { $0.title == "Import YouTube session" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
