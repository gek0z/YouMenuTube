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
            viewCount: nil,
            duration: nil,
            thumbnailURL: nil,
            isShort: true
        )
        let normal = VideoEntry(
            id: "y",
            title: "t",
            channelTitle: "c",
            timePosted: "1d ago",
            viewCount: "12K views",
            duration: "3:42",
            thumbnailURL: nil,
            isShort: false
        )
        #expect(short.isShort)
        #expect(!normal.isShort)
    }
}
