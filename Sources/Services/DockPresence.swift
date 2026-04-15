import AppKit
import Observation

/// Tracks which "dockable" windows (player, sign-in) are currently on
/// screen and flips `NSApp`'s activation policy accordingly. The app
/// launches as `.accessory` (menubar-only, LSUIElement=true) and
/// switches to `.regular` while any real window is visible, giving the
/// user a Dock icon to switch to, a standard application menu, and a
/// Cmd+Tab slot.
///
/// Identifiers are the same strings used with `openWindow(id:)`, so each
/// scene can track itself without a separate token.
@Observable
@MainActor
final class DockPresence {
    private var active: Set<String> = []

    func present(_ id: String) {
        if active.insert(id).inserted { apply() }
    }

    func dismiss(_ id: String) {
        if active.remove(id) != nil { apply() }
    }

    private func apply() {
        let target: NSApplication.ActivationPolicy = active.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != target else { return }
        NSApp.setActivationPolicy(target)
    }
}
