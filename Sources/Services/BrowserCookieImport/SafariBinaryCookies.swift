import Foundation

/// Parses Safari's `Cookies.binarycookies` file, which lives inside the
/// Safari container (`~/Library/Containers/com.apple.Safari/Data/Library/Cookies/`)
/// and is therefore only readable by our app once the user has granted
/// **Full Disk Access** in System Settings → Privacy & Security.
///
/// The file format has been stable for years and has been reverse-engineered
/// extensively (see e.g. Jeffrey Paul's notes, Satishb3's `BinaryCookieReader`).
/// Layout:
///
///   Header:
///     4B    "cook" magic
///     4B BE number of pages N
///     N×4B  BE page sizes
///     pages concatenated
///     [checksum / footer, ignored]
///
///   Page (little-endian after the 4-byte BE page tag):
///     4B    0x00000100 page tag
///     4B LE cookie count M
///     M×4B LE cookie offsets (relative to page start)
///     4B    0x00000000 terminator
///     cookies concatenated
///
///   Cookie (little-endian):
///     4B    size
///     4B    unused
///     4B    flags   (bit 0 = Secure, bit 2 = HttpOnly)
///     4B    unused
///     4B    domain offset  (relative to cookie start)
///     4B    name offset
///     4B    path offset
///     4B    value offset
///     8B    unused
///     8B    expiry   (CFAbsoluteTime, seconds since 2001-01-01 UTC)
///     8B    creation (CFAbsoluteTime)
///     NUL-terminated strings at the declared offsets
enum SafariBinaryCookies {
    static func read(at storeURL: URL, domainSuffix: String) throws -> [HTTPCookie] {
        let data: Data
        do {
            data = try Data(contentsOf: storeURL, options: [.mappedIfSafe])
        } catch {
            if let ns = error as NSError?, ns.domain == NSCocoaErrorDomain,
                ns.code == NSFileReadNoPermissionError || ns.code == NSFileReadUnknownError
            {
                throw BrowserCookieError.tccDenied
            }
            if !FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) {
                throw BrowserCookieError.storeMissing(storeURL)
            }
            // macOS returns "operation not permitted" for TCC-blocked reads,
            // which Foundation surfaces as generic; treat any read failure
            // on a path that exists as TCC-denied, user can retry after
            // granting Full Disk Access.
            throw BrowserCookieError.tccDenied
        }

        guard data.count >= 12 else { throw BrowserCookieError.storeRead("binarycookies too small") }
        guard data.prefix(4) == Data("cook".utf8) else {
            throw BrowserCookieError.storeRead("binarycookies missing 'cook' magic")
        }

        let pageCount = Int(data.readUInt32BE(at: 4))
        guard pageCount > 0 else { return [] }
        let headerEnd = 8 + pageCount * 4
        guard data.count >= headerEnd else {
            throw BrowserCookieError.storeRead("binarycookies header truncated")
        }

        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(pageCount)
        for i in 0..<pageCount {
            pageSizes.append(Int(data.readUInt32BE(at: 8 + i * 4)))
        }

        var cookies: [HTTPCookie] = []
        var offset = headerEnd
        for size in pageSizes {
            guard offset + size <= data.count else {
                throw BrowserCookieError.storeRead("binarycookies page overruns file")
            }
            let page = data.subdata(in: offset..<(offset + size))
            try parsePage(page, into: &cookies, domainSuffix: domainSuffix)
            offset += size
        }
        return cookies
    }

    private static func parsePage(_ page: Data, into cookies: inout [HTTPCookie], domainSuffix: String) throws {
        guard page.count >= 12 else { return }
        // Page tag is 4 bytes but we don't validate it strictly, some
        // Safari builds have varied the first byte.
        let cookieCount = Int(page.readUInt32LE(at: 4))
        guard cookieCount > 0, page.count >= 8 + cookieCount * 4 + 4 else { return }

        var cookieOffsets: [Int] = []
        cookieOffsets.reserveCapacity(cookieCount)
        for i in 0..<cookieCount {
            cookieOffsets.append(Int(page.readUInt32LE(at: 8 + i * 4)))
        }

        for cookieOffset in cookieOffsets {
            guard cookieOffset + 56 <= page.count else { continue }
            if let cookie = parseCookie(page: page, at: cookieOffset, domainSuffix: domainSuffix) {
                cookies.append(cookie)
            }
        }
    }

    private static func parseCookie(page: Data, at offset: Int, domainSuffix: String) -> HTTPCookie? {
        let size = Int(page.readUInt32LE(at: offset))
        guard size >= 56, offset + size <= page.count else { return nil }
        let rec = page.subdata(in: offset..<(offset + size))

        let flags = rec.readUInt32LE(at: 8)
        let domainOff = Int(rec.readUInt32LE(at: 16))
        let nameOff = Int(rec.readUInt32LE(at: 20))
        let pathOff = Int(rec.readUInt32LE(at: 24))
        let valueOff = Int(rec.readUInt32LE(at: 28))
        let expiryAbs = rec.readDoubleLE(at: 40)

        guard let domain = rec.readCString(at: domainOff),
            let name = rec.readCString(at: nameOff),
            let path = rec.readCString(at: pathOff),
            let value = rec.readCString(at: valueOff)
        else { return nil }

        // Early domain filter, 99% of cookies won't match, and this avoids
        // building HTTPCookie objects we'd drop anyway.
        guard domain.hasSuffix(domainSuffix) else { return nil }

        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
        ]
        if expiryAbs > 0 {
            // Safari stores expiry as CFAbsoluteTime (seconds since 2001-01-01).
            let unixSeconds = expiryAbs + Date.timeIntervalBetween1970AndReferenceDate
            props[.expires] = Date(timeIntervalSince1970: unixSeconds)
        }
        if (flags & 0x1) != 0 { props[.secure] = "TRUE" }
        let isHttpOnly = (flags & 0x4) != 0
        props[HTTPCookiePropertyKey("HttpOnly")] = isHttpOnly ? "TRUE" : "FALSE"
        return HTTPCookie(properties: props)
    }
}

// MARK: - Data byte helpers

extension Data {
    fileprivate func readUInt32BE(at offset: Int) -> UInt32 {
        let b = self[self.startIndex + offset..<self.startIndex + offset + 4]
        return b.withUnsafeBytes { ptr in
            let raw = ptr.loadUnaligned(as: UInt32.self)
            return UInt32(bigEndian: raw)
        }
    }

    fileprivate func readUInt32LE(at offset: Int) -> UInt32 {
        let b = self[self.startIndex + offset..<self.startIndex + offset + 4]
        return b.withUnsafeBytes { ptr in
            let raw = ptr.loadUnaligned(as: UInt32.self)
            return UInt32(littleEndian: raw)
        }
    }

    fileprivate func readDoubleLE(at offset: Int) -> Double {
        let b = self[self.startIndex + offset..<self.startIndex + offset + 8]
        return b.withUnsafeBytes { ptr in
            let raw = ptr.loadUnaligned(as: UInt64.self)
            return Double(bitPattern: UInt64(littleEndian: raw))
        }
    }

    /// Reads a NUL-terminated UTF-8 string starting at `offset`. Returns
    /// nil if no NUL is found before end of data.
    fileprivate func readCString(at offset: Int) -> String? {
        guard offset < self.count else { return nil }
        let start = self.startIndex + offset
        guard let nulIdx = self[start..<self.endIndex].firstIndex(of: 0) else { return nil }
        return String(data: self[start..<nulIdx], encoding: .utf8)
    }
}
