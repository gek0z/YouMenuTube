import Foundation

extension Array {
    /// Returns elements with unique values at `keyPath`, keeping the first
    /// occurrence. Used to normalise model arrays before handing them to
    /// `ForEach` — YouTubeKit occasionally returns the same video id twice
    /// in one response (e.g. a shelf item that also appears inline), which
    /// triggers SwiftUI runtime warnings about duplicate ids.
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        seen.reserveCapacity(count)
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
