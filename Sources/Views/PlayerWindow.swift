import SwiftUI
import WebKit

struct PlayerWindow: View {
    @Environment(PlayerController.self) private var player
    @AppStorage("player.autoplay") private var autoplay: Bool = true

    var body: some View {
        Group {
            if let vid = player.videoId {
                YouTubeEmbedView(videoId: vid, autoplay: autoplay)
                    .frame(minWidth: 640, minHeight: 360)
                    .navigationTitle(player.title ?? "YouMenuTube")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Pick a video from the menu bar.").foregroundStyle(.secondary)
                }
                .frame(width: 420, height: 240)
            }
        }
    }
}

struct YouTubeEmbedView: NSViewRepresentable {
    let videoId: String
    let autoplay: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        // Same Safari UA spoof as the sign-in view — YouTube's embed player
        // also fingerprints WKWebView's default UA and shows error 152-4.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(into: nsView, coordinator: context.coordinator)
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        // Only reload when the actual video changes. Comparing WKWebView.url
        // against our target URL is unreliable because YouTube rewrites the
        // iframe URL with extra query params, which would cause infinite reloads.
        guard coordinator.loadedKey != key else { return }
        coordinator.loadedKey = key

        let ap = autoplay ? 1 : 0
        // YouTube's embed needs to live inside an iframe whose parent has a
        // distinct, real-looking origin. Top-level load → error 153.
        // baseURL=youtube.com (same-origin parent) → error 152-4.
        // baseURL=nil (about:blank parent) → restricted permissions, also fails.
        // A fake https origin gives the iframe a real cross-origin parent and
        // a valid Referer, which is the combination the IFrame player accepts.
        let host = "youmenutube.local"
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; padding: 0; background: #000; height: 100%; overflow: hidden; }
              iframe { border: 0; width: 100%; height: 100%; }
            </style>
          </head>
          <body>
            <iframe
              src="https://www.youtube.com/embed/\(videoId)?autoplay=\(ap)&playsinline=1&rel=0&modestbranding=1&origin=https://\(host)"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen"
              allowfullscreen></iframe>
          </body>
        </html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://\(host)/")!)
    }

    private var key: String { "\(videoId)|\(autoplay)" }

    final class Coordinator {
        var loadedKey: String?
    }
}
