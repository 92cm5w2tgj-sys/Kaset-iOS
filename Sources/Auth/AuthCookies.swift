import CryptoKit
import Foundation

// Adapted from kaset: Services/WebKit/WebKitManager+Cookies.swift (allowlist, validity,
// archive), WebKitManager+AuthMaterial.swift (domain matching, SAPISID selection) and
// Services/API/InnerTubeSupport.swift (SAPISIDHASH). The restore-policy/transaction
// machinery is intentionally not copied: the iOS app archives one blob in the Keychain.

/// What an InnerTube request needs from the cookie jar.
struct AuthMaterial: Equatable {
    let cookieHeader: String
    let sapisid: String
}

enum AuthCookies {
    static let origin = "https://music.youtube.com"
    static let primaryCookieName = "__Secure-3PAPISID"
    static let fallbackCookieName = "SAPISID"

    /// Explicit YouTube/Google session-cookie allowlist used for native API auth.
    static let names: Set<String> = [
        "SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID",
        "SID", "HSID", "SSID", "APISID",
        "LOGIN_INFO", "SIDCC",
        "__Secure-1PSID", "__Secure-3PSID",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        "__Secure-1PSIDTS", "__Secure-3PSIDTS",
    ]

    static func isAllowedDomain(_ domain: String) -> Bool {
        let normalized = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop(while: { $0 == "." })
        guard !normalized.isEmpty else { return false }
        return ["youtube.com", "google.com"].contains { root in
            normalized == root || normalized.hasSuffix(".\(root)")
        }
    }

    static func isAuthCookie(_ cookie: HTTPCookie) -> Bool {
        self.names.contains(cookie.name) && self.isAllowedDomain(cookie.domain)
    }

    static func isValid(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        guard self.isAuthCookie(cookie) else { return false }
        if let expires = cookie.expiresDate, expires < now { return false }
        return true
    }

    static func cookies(_ cookies: [HTTPCookie], matching domain: String) -> [HTTPCookie] {
        let target = domain.lowercased()
        return cookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased()
            if cookieDomain == target { return true }
            if cookieDomain.hasPrefix(".") {
                let bare = String(cookieDomain.dropFirst())
                return target == bare || target.hasSuffix("." + bare)
            }
            return target.hasSuffix("." + cookieDomain)
        }
    }

    /// Cookie header and SAPISID for `youtube.com`. Secure-first: an expired
    /// `__Secure-3PAPISID` means expired auth even if a fallback cookie exists.
    static func material(from cookies: [HTTPCookie], now: Date = Date()) -> AuthMaterial? {
        let domainCookies = self.cookies(cookies, matching: "youtube.com")
        guard !domainCookies.isEmpty,
              let header = HTTPCookie.requestHeaderFields(with: domainCookies)["Cookie"]
        else { return nil }

        let primary = domainCookies.first { $0.name == self.primaryCookieName }
        let fallback = domainCookies.first { $0.name == self.fallbackCookieName }
        guard let authCookie = primary ?? fallback else { return nil }
        if let expires = authCookie.expiresDate, expires < now { return nil }
        return AuthMaterial(cookieHeader: header, sapisid: authCookie.value)
    }

    /// `SHA1("<ts> <sapisid> <origin>")`, formatted `<ts>_<hex>`. The origin is part of the
    /// hash, so a value for music.youtube.com is not valid for www.youtube.com.
    static func sapisidHash(sapisid: String, origin: String = AuthCookies.origin, timestamp: Int) -> String {
        let input = "\(timestamp) \(sapisid) \(origin)"
        let hex = Insecure.SHA1.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(timestamp)_\(hex)"
    }

    // MARK: - Archive

    /// Serializes the valid auth cookies, or `nil` when there is no primary session cookie.
    static func archive(_ cookies: [HTTPCookie], now: Date = Date()) -> Data? {
        let valid = cookies
            .filter { self.isValid($0, now: now) }
            .sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
        let hasPrimary = self.cookies(valid, matching: "youtube.com").contains {
            $0.name == self.primaryCookieName || $0.name == self.fallbackCookieName
        }
        guard hasPrimary else { return nil }

        let properties: [[String: Any]] = valid.compactMap { cookie in
            guard let raw = cookie.properties else { return nil }
            var result: [String: Any] = [:]
            for (key, value) in raw {
                // Property lists only hold these; drops e.g. the comment URL.
                if value is String || value is Date || value is NSNumber {
                    result[key.rawValue] = value
                }
            }
            return result
        }
        return try? PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
    }

    static func restore(from data: Data, now: Date = Date()) -> [HTTPCookie] {
        guard let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [[String: Any]]
        else { return [] }
        return list
            .compactMap { entry -> HTTPCookie? in
                var properties: [HTTPCookiePropertyKey: Any] = [:]
                for (key, value) in entry { properties[HTTPCookiePropertyKey(key)] = value }
                return HTTPCookie(properties: properties)
            }
            .filter { self.isValid($0, now: now) }
    }
}
