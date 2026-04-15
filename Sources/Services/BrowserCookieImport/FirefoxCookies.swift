import Foundation
import SQLite3

/// Reads cookies out of Firefox's `cookies.sqlite`. Firefox stores cookie
/// values in plaintext, so no key derivation or decryption is needed, just
/// SQLite.
///
/// The file can be opened even while Firefox is running because we open it
/// read-only with the URI query `?immutable=1`, which tells SQLite to skip
/// locking and journaling inspection.
enum FirefoxCookies {
    static func read(at storeURL: URL, domainSuffix: String) throws -> [HTTPCookie] {
        try SQLiteReader.read(storeURL: storeURL) { db in
            // moz_cookies columns (stable since Firefox 4):
            //   host, name, value, path, expiry, isSecure, isHttpOnly
            let sql = """
                SELECT host, name, value, path, expiry, isSecure, isHttpOnly
                FROM moz_cookies
                WHERE host LIKE ?
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw BrowserCookieError.storeRead("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, "%\(domainSuffix)", -1, SQLiteReader.sqliteTransient)

            var cookies: [HTTPCookie] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let host = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                    let name = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
                    let value = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
                    let path = sqlite3_column_text(stmt, 3).map({ String(cString: $0) })
                else { continue }
                let expiry = sqlite3_column_int64(stmt, 4)
                let isSecure = sqlite3_column_int(stmt, 5) != 0
                let isHttpOnly = sqlite3_column_int(stmt, 6) != 0
                if let c = Self.makeCookie(
                    host: host, name: name, value: value, path: path,
                    expiryUnix: Double(expiry), isSecure: isSecure, isHttpOnly: isHttpOnly)
                {
                    cookies.append(c)
                }
            }
            return cookies
        }
    }

    private static func makeCookie(
        host: String, name: String, value: String, path: String,
        expiryUnix: Double, isSecure: Bool, isHttpOnly: Bool
    ) -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: host,
            .path: path.isEmpty ? "/" : path,
        ]
        if expiryUnix > 0 {
            props[.expires] = Date(timeIntervalSince1970: expiryUnix)
        }
        if isSecure { props[.secure] = "TRUE" }
        // HTTPCookiePropertyKey has no built-in HttpOnly key, but we preserve
        // it for completeness using the raw string Apple recognises.
        props[HTTPCookiePropertyKey("HttpOnly")] = isHttpOnly ? "TRUE" : "FALSE"
        return HTTPCookie(properties: props)
    }
}
