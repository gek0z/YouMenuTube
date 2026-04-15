import CommonCrypto
import Foundation
import LocalAuthentication
import SQLite3
import Security

/// Reads cookies out of a Chromium-family browser's SQLite cookie store and
/// decrypts the encrypted values using the browser's Safe Storage key from
/// the macOS login Keychain.
///
/// Crypto constants come from Chromium's
/// `components/os_crypt/sync/os_crypt_mac.mm` and have been stable since
/// Chrome 80 (2020):
///   - PBKDF2-HMAC-SHA1, 1003 iterations, salt "saltysalt", 16-byte key
///   - AES-128-CBC, IV = 16 spaces
///   - `v10` prefix on encrypted values (v11 in some Linux builds; same
///     cipher on macOS, treated identically here)
enum ChromiumCookies {
    static func read(browser: Browser, storeURL: URL, domainSuffix: String) throws -> [HTTPCookie] {
        guard browser.format == .chromium else {
            throw BrowserCookieError.storeRead("non-Chromium browser passed to ChromiumCookies.read")
        }
        guard let service = browser.chromiumSafeStorageService,
            let account = browser.chromiumSafeStorageAccount
        else {
            throw BrowserCookieError.storeRead("missing Safe Storage service/account for \(browser.rawValue)")
        }

        let password = try fetchSafeStoragePassword(service: service, account: account, browser: browser)
        let key = deriveKey(fromPassword: password)

        return try SQLiteReader.read(storeURL: storeURL) { db in
            // Chromium's `cookies` table has had a stable-enough shape for
            // our purposes since Chrome 80. `expires_utc` is in Chromium's
            // epoch (microseconds since 1601-01-01 UTC).
            let sql = """
                SELECT host_key, name, encrypted_value, value, path, expires_utc, is_secure, is_httponly
                FROM cookies
                WHERE host_key LIKE ?
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
                    let name = sqlite3_column_text(stmt, 1).map({ String(cString: $0) })
                else { continue }

                let encryptedSize = sqlite3_column_bytes(stmt, 2)
                let plainValue = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""

                let value: String
                if encryptedSize > 0, let blob = sqlite3_column_blob(stmt, 2) {
                    let data = Data(bytes: blob, count: Int(encryptedSize))
                    if let decrypted = Self.decrypt(data, key: key, hostKey: host) {
                        value = decrypted
                    } else {
                        // Value was encrypted but we couldn't decrypt it,
                        // skip rather than ship a corrupt cookie.
                        continue
                    }
                } else {
                    value = plainValue
                }

                let path = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "/"
                let expiresUtc = sqlite3_column_int64(stmt, 5)
                let isSecure = sqlite3_column_int(stmt, 6) != 0
                let isHttpOnly = sqlite3_column_int(stmt, 7) != 0

                if let c = Self.makeCookie(
                    host: host, name: name, value: value, path: path,
                    expiresUtcChromium: expiresUtc, isSecure: isSecure, isHttpOnly: isHttpOnly)
                {
                    cookies.append(c)
                }
            }
            return cookies
        }
    }

    // MARK: - Keychain

    private static func fetchSafeStoragePassword(service: String, account: String, browser: Browser) throws -> String {
        // Passing an LAContext lets the system upgrade the prompt to Touch
        // ID on Macs that have it enrolled, but only if the keychain
        // item's ACL was created with biometric-compatible flags. Chromium
        // browsers don't do that when they add their Safe Storage key, so
        // in practice the OS still falls back to a password prompt. Harmless
        // to pass it either way; costs nothing and gives Touch ID to any
        // future Chromium build whose ACL ever gains biometric support.
        let context = LAContext()
        context.localizedReason = "Import your YouTube session from \(browser.displayName)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "read \(browser.displayName)'s cookie-encryption key",
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let pw = String(data: data, encoding: .utf8) else {
                throw BrowserCookieError.keychainDenied(browser)
            }
            return pw
        case errSecItemNotFound:
            throw BrowserCookieError.notSignedIn(browser, reason: "no Safe Storage key for \(service)")
        case errSecUserCanceled, errSecAuthFailed:
            throw BrowserCookieError.keychainDenied(browser)
        default:
            throw BrowserCookieError.storeRead("SecItemCopyMatching: status=\(status)")
        }
    }

    // MARK: - Crypto

    private static func deriveKey(fromPassword password: String) -> Data {
        let salt = "saltysalt"
        let keyLength = 16
        let iterations: UInt32 = 1003
        var key = Data(count: keyLength)
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array(salt.utf8)
        _ = key.withUnsafeMutableBytes { keyPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, passwordBytes.count,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                iterations,
                keyPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                keyLength
            )
        }
        return key
    }

    private static func decrypt(_ blob: Data, key: Data, hostKey: String) -> String? {
        // v10 (and v11 on Linux) have a 3-byte version prefix; strip it.
        // Anything without the prefix is a plain legacy value we should not
        // have reached (the plain value is in the `value` column, not
        // `encrypted_value`), so treat as undecipherable.
        guard blob.count > 3,
            let prefix = String(data: blob.prefix(3), encoding: .utf8),
            prefix == "v10" || prefix == "v11"
        else { return nil }
        let ciphertext = Array(blob.suffix(from: blob.startIndex + 3))
        let keyBytes = Array(key)
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        let outCapacity = ciphertext.count + kCCBlockSizeAES128
        var out = [UInt8](repeating: 0, count: outCapacity)
        var outLen = 0

        let rc = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes, keyBytes.count,
            iv,
            ciphertext, ciphertext.count,
            &out, outCapacity,
            &outLen
        )
        guard rc == kCCSuccess else { return nil }
        let plaintext = Array(out.prefix(outLen))

        // Modern Chromium (Chrome 91+ and downstream forks) prepends the
        // first 16 bytes of SHA256(host_key) to the plaintext before
        // encrypting, as an integrity binding that prevents an attacker
        // from swapping an encrypted value between hosts.
        //
        // Even newer Chromium builds (observed on macOS with Chrome
        // 146-era and Imputnet's Helium) prepend an *additional* 16-byte
        // block after the host hash. Its derivation isn't documented in
        // public Chromium source but it's constant per machine and
        // consistent across Chromium-family browsers on that machine.
        //
        // Strategy: strip the host-hash prefix if present, then peel one
        // more 16-byte block if the next byte looks like binary (cookie
        // values are always printable ASCII / base64 in practice). Cap
        // the peel at one extra block to avoid eating a legitimate value.
        let hostHashPrefix = Self.sha256Prefix16(of: hostKey)
        var body = plaintext[...]
        if body.count >= 16, body.prefix(16).elementsEqual(hostHashPrefix) {
            body = body.dropFirst(16)
        }
        if let first = body.first, !Self.looksLikePrintable(first), body.count >= 16 {
            body = body.dropFirst(16)
        }
        return String(bytes: body, encoding: .utf8)
    }

    private static func looksLikePrintable(_ byte: UInt8) -> Bool {
        byte >= 0x20 && byte < 0x7F
    }

    private static func sha256Prefix16(of string: String) -> [UInt8] {
        let bytes = Array(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(bytes, CC_LONG(bytes.count), &digest)
        return Array(digest.prefix(16))
    }

    // MARK: - Cookie assembly

    /// Chromium stores `expires_utc` as microseconds since 1601-01-01 UTC
    /// (the Windows FILETIME epoch). Convert to Foundation's seconds-since-1970.
    private static func makeCookie(
        host: String, name: String, value: String, path: String,
        expiresUtcChromium: Int64, isSecure: Bool, isHttpOnly: Bool
    ) -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: host,
            .path: path.isEmpty ? "/" : path,
        ]
        if expiresUtcChromium > 0 {
            let unixSeconds = Double(expiresUtcChromium) / 1_000_000.0 - 11_644_473_600.0
            if unixSeconds > Date().timeIntervalSince1970 - 60 {
                props[.expires] = Date(timeIntervalSince1970: unixSeconds)
            }
        }
        if isSecure { props[.secure] = "TRUE" }
        props[HTTPCookiePropertyKey("HttpOnly")] = isHttpOnly ? "TRUE" : "FALSE"
        return HTTPCookie(properties: props)
    }
}
