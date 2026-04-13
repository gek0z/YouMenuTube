import AppKit
import SwiftUI
import WebKit

struct PlayerWindow: View {
    @Environment(PlayerController.self) private var player
    @Environment(DockPresence.self) private var dock
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("player.autoplay") private var autoplay: Bool = true
    @AppStorage("player.floatOnTop") private var floatOnTop: Bool = true
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .top) {
            content
            // Hover-revealed strip at the top: drag area + close button.
            // Hidden when mouse leaves so YouTube's own overlay controls
            // (title, more menu) remain clickable through the WKWebView.
            if isHovering {
                ZStack(alignment: .leading) {
                    DragHandle()
                    HStack(spacing: 6) {
                        overlayButton(system: "xmark.circle.fill", help: "Close") {
                            player.stop()
                            dismissWindow(id: WindowID.player)
                        }
                        overlayButton(
                            system: floatOnTop ? "pin.circle.fill" : "pin.circle",
                            help: floatOnTop ? "Stop floating on top" : "Float on top"
                        ) {
                            floatOnTop.toggle()
                        }
                    }
                    .padding(.leading, 8)
                }
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .background(WindowConfigurator(floatOnTop: floatOnTop))
        .onAppear {
            dock.present(WindowID.player)
            bringToFront()
        }
        .onChange(of: player.videoId) { _, newId in
            // Playing a fresh video while the window is already open
            // should still pull focus — otherwise the menubar click
            // swaps the video silently in the background.
            if newId != nil { bringToFront() }
        }
        .onDisappear { dock.dismiss(WindowID.player) }
    }

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        // Schedule the makeKey one runloop later: on the first open the
        // NSWindow hasn't been fully wired up when onAppear fires.
        Task { @MainActor in
            NSApp.windows
                .first { $0.title == "Now Playing" }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private func overlayButton(
        system: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var content: some View {
        if let vid = player.videoId {
            YouTubeEmbedView(videoId: vid, autoplay: autoplay)
                .frame(minWidth: 240, minHeight: 135)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary)
                Text("Pick a video from the menu bar.").foregroundStyle(.secondary)
            }
            .frame(minWidth: 240, minHeight: 135)
        }
    }
}

/// Tiny NSView whose only job is to forward mouse-down to NSWindow.performDrag,
/// giving us a draggable region inside an otherwise event-consuming WKWebView.
private struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableNSView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class DraggableNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Reaches into the underlying NSWindow to hide the traffic-light buttons,
/// keep the window draggable from its (now-invisible) title bar area, and
/// toggle the floating level whenever the user changes the preference.
private struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = WindowAwareView()
        view.onWindow = { [floatOnTop] window in apply(to: window, floatOnTop: floatOnTop) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window, floatOnTop: floatOnTop)
    }

    private func apply(to window: NSWindow?, floatOnTop: Bool) {
        guard let window else { return }
        window.level = floatOnTop ? .floating : .normal
        // Just raising level isn't enough once the window has been ordered
        // behind a normal-level window from another app: AppKit leaves it
        // where it is and the user sees no change. Ask for a fresh stacking
        // pass so the newly-floating window actually comes back to the top.
        if floatOnTop { window.orderFrontRegardless() }
        window.isMovableByWindowBackground = true
        // .plain windows are .borderless, which means they can't become key
        // (Cmd+W won't fire) and have no resize handles. Inserting .resizable
        // gives back both: edge-resize works and the window accepts keyboard
        // shortcuts targeting it.
        window.styleMask.insert(.resizable)
        window.aspectRatio = NSSize(width: 16, height: 9)
        window.minSize = NSSize(width: 240, height: 135)
    }
}

private final class WindowAwareView: NSView {
    var onWindow: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
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
        view.customUserAgent = UserAgent.safari
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
