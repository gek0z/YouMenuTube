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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        load(into: view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(into: nsView)
    }

    private func load(into view: WKWebView) {
        let ap = autoplay ? 1 : 0
        let url = URL(string: "https://www.youtube.com/embed/\(videoId)?autoplay=\(ap)&playsinline=1&rel=0")!
        if view.url != url { view.load(URLRequest(url: url)) }
    }
}
