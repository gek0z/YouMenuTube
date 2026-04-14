import Foundation
import SQLite3

/// Opens a browser cookie SQLite store read-only and hands the raw db
/// handle to a closure. Shared between the Firefox and Chromium readers.
///
/// Chrome / Firefox lock the cookies file with a journal when running, but
/// opening read-only with `immutable=1` tells SQLite not to inspect the
/// journal or acquire any locks. This is the trick yt-dlp uses.
enum SQLiteReader {
    /// SQLite's SQLITE_TRANSIENT macro tells sqlite3_bind_* to copy the
    /// buffer it points at. Not exposed by the Swift SQLite3 module, so we
    /// bridge it by hand.
    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func read<T>(storeURL: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        let uri = "file:\(storeURL.path(percentEncoded: false))?immutable=1"
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let openRc = sqlite3_open_v2(uri, &db, flags, nil)
        guard openRc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "rc=\(openRc)"
            if let db { sqlite3_close(db) }
            if openRc == SQLITE_CANTOPEN {
                throw BrowserCookieError.storeMissing(storeURL)
            }
            throw BrowserCookieError.storeRead("open failed: \(msg)")
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }
}
