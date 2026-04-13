import OSLog
import Observation
import SwiftUI
import WebKit

private let signInLog = Logger(subsystem: "app.youmenutube", category: "signin")

@Observable
@MainActor
final class SignInWebViewHolder: NSObject, WKNavigationDelegate {
    var currentURL: URL?
    @ObservationIgnored var webView: WKWebView?

    var isAtYouTube: Bool {
        guard let host = currentURL?.host else { return false }
        return host == "www.youtube.com" || host == "youtube.com" || host == "m.youtube.com"
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            signInLog.debug("nav start → \(webView.url?.absoluteString ?? "nil", privacy: .public)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            self.currentURL = webView.url
            signInLog.debug("nav commit → \(webView.url?.absoluteString ?? "nil", privacy: .public)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            self.currentURL = webView.url
            signInLog.debug("nav finish → \(webView.url?.absoluteString ?? "nil", privacy: .public)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            signInLog.error("nav fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        MainActor.assumeIsolated {
            signInLog.error("nav fail (provisional): \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct YouTubeSignInWindow: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(DockPresence.self) private var dock
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isCapturing = false
    @State private var didAutoCapture = false
    @State private var holder = SignInWebViewHolder()

    var body: some View {
        VStack(spacing: 0) {
            SignInWebView(holder: holder) { webView in
                Task {
                    signInLog.notice("clearing websiteData for youtube.com / google.com")
                    await yt.clearWebSignInState()
                    signInLog.notice("loading https://www.youtube.com/signin")
                    webView.load(URLRequest(url: URL(string: "https://www.youtube.com/signin")!))
                }
            }
            .frame(minWidth: 720, minHeight: 720)

            Divider()
            HStack(alignment: .center, spacing: 10) {
                if isCapturing { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        holder.isAtYouTube
                            ? "On youtube.com — click Done to capture the session."
                            : "Complete sign-in, then let the page land on youtube.com.")
                    Text(holder.currentURL?.absoluteString ?? "loading…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismissWindow(id: WindowID.signIn) }
                Button {
                    Task {
                        isCapturing = true
                        defer { isCapturing = false }
                        let ok = await yt.captureCookiesFromSharedStore()
                        if ok { dismissWindow(id: WindowID.signIn) }
                    }
                } label: {
                    Text("Done").frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing || !holder.isAtYouTube)
                .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            dock.present(WindowID.signIn)
        }
        .onDisappear { dock.dismiss(WindowID.signIn) }
        .onChange(of: holder.isAtYouTube) { _, onYouTube in
            // Once the webview lands on youtube.com, try to capture silently.
            // If session cookies are present we're done; otherwise the user
            // can still finish the flow and click Done manually.
            guard onYouTube, !didAutoCapture, !isCapturing else { return }
            didAutoCapture = true
            Task {
                isCapturing = true
                defer { isCapturing = false }
                let ok = await yt.captureCookiesFromSharedStore()
                if ok {
                    signInLog.notice("auto-capture succeeded — closing sign-in window")
                    dismissWindow(id: WindowID.signIn)
                } else {
                    signInLog.notice("auto-capture deferred — waiting for user")
                    didAutoCapture = false
                }
            }
        }
    }
}

private struct SignInWebView: NSViewRepresentable {
    let holder: SignInWebViewHolder

    let onReady: (WKWebView) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = UserAgent.safari
        view.navigationDelegate = holder
        holder.webView = view
        onReady(view)
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
