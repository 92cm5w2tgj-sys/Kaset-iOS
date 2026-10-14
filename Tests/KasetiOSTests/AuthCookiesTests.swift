import Foundation
import Testing

@testable import KasetiOS

struct AuthCookiesTests {
    private func cookie(
        _ name: String, _ value: String = "v", domain: String = ".youtube.com", expires: Date? = Date().addingTimeInterval(3600)
    ) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE",
        ]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    @Test func sapisidHashMatchesKnownVector() {
        let hash = AuthCookies.sapisidHash(sapisid: "abc", origin: "https://music.youtube.com", timestamp: 1_700_000_000)
        #expect(hash == "1700000000_2f3ec011e870f3fbd0238c090c2062c208cead32")
    }

    @Test func originIsPartOfTheHash() {
        let music = AuthCookies.sapisidHash(sapisid: "abc", origin: "https://music.youtube.com", timestamp: 1)
        let www = AuthCookies.sapisidHash(sapisid: "abc", origin: "https://www.youtube.com", timestamp: 1)
        #expect(music != www)
    }

    @Test func materialPrefersSecureCookie() {
        let jar = [cookie("SAPISID", "fallback"), cookie("__Secure-3PAPISID", "secure")]
        #expect(AuthCookies.material(from: jar)?.sapisid == "secure")
    }

    @Test func expiredSecureCookieMeansExpiredAuth() {
        let jar = [
            cookie("__Secure-3PAPISID", "old", expires: Date().addingTimeInterval(-10)),
            cookie("SAPISID", "fallback"),
        ]
        #expect(AuthCookies.material(from: jar) == nil)
    }

    @Test func noCookiesMeansNoMaterial() {
        #expect(AuthCookies.material(from: []) == nil)
        #expect(AuthCookies.material(from: [cookie("PREF", domain: ".youtube.com")])?.sapisid == nil)
    }

    @Test func headerOnlyContainsYouTubeCookies() throws {
        let jar = [cookie("SAPISID", "s"), cookie("OTHER", "x", domain: "example.com")]
        let header = try #require(AuthCookies.material(from: jar)?.cookieHeader)
        #expect(header.contains("SAPISID=s"))
        #expect(!header.contains("OTHER"))
    }

    @Test func archiveRoundTripKeepsOnlyAuthCookies() throws {
        let jar = [
            cookie("SAPISID", "s"), cookie("SID", "sid"), cookie("PREF", "tracking"),
            cookie("HSID", "x", domain: "evil.example.com"),
        ]
        let data = try #require(AuthCookies.archive(jar))
        let restored = AuthCookies.restore(from: data)
        #expect(Set(restored.map(\.name)) == ["SAPISID", "SID"])
        #expect(restored.first { $0.name == "SAPISID" }?.value == "s")
        #expect(restored.first { $0.name == "SAPISID" }?.domain == ".youtube.com")
    }

    @Test func archiveRequiresAPrimarySessionCookie() {
        #expect(AuthCookies.archive([cookie("SID", "sid")]) == nil)
    }

    @Test func restoreDropsExpiredCookies() throws {
        let data = try #require(AuthCookies.archive([cookie("SAPISID", "s"), cookie("SID", "sid")]))
        let later = Date().addingTimeInterval(7200)
        #expect(AuthCookies.restore(from: data, now: later).isEmpty)
    }

    @Test func vaultRoundTrip() {
        let vault = InMemoryCookieVault()
        #expect(vault.load() == nil)
        vault.save(Data([1, 2]))
        #expect(vault.load() == Data([1, 2]))
        vault.delete()
        #expect(vault.load() == nil)
    }
}
