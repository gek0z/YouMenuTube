import Foundation
import Observation

/// Shared "the user pressed refresh" signal. Tab views observe `counter` via
/// `.task(id: refresh.counter)` and reload when it bumps; the main header
/// button calls `ping()`.
@Observable
@MainActor
final class RefreshTrigger {
    var counter: Int = 0

    func ping() {
        counter &+= 1
    }
}
