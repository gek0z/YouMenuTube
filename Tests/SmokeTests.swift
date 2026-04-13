import Foundation
import Testing

@testable import YouMenuTube

@Suite("VideoEntry")
struct VideoEntryTests {
    @Test("isShort flag round-trips through the initialiser")
    func isShortRoundTrips() {
        let short = VideoEntry(
            id: "x",
            title: "t",
            channelTitle: nil,
            timePosted: nil,
            thumbnailURL: nil,
            isShort: true
        )
        let normal = VideoEntry(
            id: "y",
            title: "t",
            channelTitle: "c",
            timePosted: "1d ago",
            thumbnailURL: nil,
            isShort: false
        )
        #expect(short.isShort)
        #expect(!normal.isShort)
    }
}
