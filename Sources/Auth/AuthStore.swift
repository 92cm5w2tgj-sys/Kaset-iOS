import Foundation
import Observation
import WebKit

enum AuthState: Equatable {
    /// Before `restore()` finished.
    case unknown
    case signedOut
    case signedIn
}

/// Source of truth for "am I signed in", and keeper of the cookie archive.
///
/// There is no OAuth token: the Google cookies in the shared `WKWebsiteDataStore` are the
/// session. They are mirrored to the Keychain so a relaunch (or an OS-evicted web data
/// store) does not sign the user out, and the same jar feeds `SAPISIDHASH` signing.
@MainActor
@Observable
final class AuthStore {
    private(set) var state: AuthState = .unknown

    @ObservationIgnored private let vault: CookieVault
    @ObservationIgnored private let dataStore: WKWebsiteDataStore
    @ObservationIgnored private var observer: CookieObserver?
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(vault: CookieVault = KeychainCookieVault(), dataStore: WKWebsiteDataStore = .default()) {
        self.vault = vault
        self.dataStore = dataStore
    }

    private var cookieStore: WKHTTPCookieStore { self.dataStore.httpCookieStore }

    // MARK: - Lifecycle

    /// Puts the archived cookies back into the web view jar when it lost them, then decides
    /// the state. Returns `true` if cookies were restored (callers reload live web views).
    @discardableResult
    func restore() async -> Bool {
        var restored = false
        let live = await self.cookieStore.allCookies()
        if AuthCookies.material(from: live) == nil, let data = self.vault.load() {
            let cookies = AuthCookies.restore(from: data)
            for cookie in cookies { await self.cookieStore.setCookie(cookie) }
            restored = !cookies.isEmpty
        }

        let jar = await self.cookieStore.allCookies()
        self.state = AuthCookies.material(from: jar) == nil ? .signedOut : .signedIn
        if self.state == .signedIn {
            self.persist(jar)
            self.startObserving()
        }
        return restored
    }

    /// Called when the login web view reached music.youtube.com. Returns whether a session exists.
    @discardableResult
    func loginFinished() async -> Bool {
        let jar = await self.cookieStore.allCookies()
        guard AuthCookies.material(from: jar) != nil else { return false }
        self.persist(jar)
        self.state = .signedIn
        self.startObserving()
        return true
    }

    func signOut() async {
        self.persistTask?.cancel()
        self.state = .signedOut
        self.vault.delete()
        for cookie in await self.cookieStore.allCookies() where AuthCookies.isAllowedDomain(cookie.domain) {
            await self.cookieStore.deleteCookie(cookie)
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await self.dataStore.dataRecords(ofTypes: types)
            .filter { $0.displayName.contains("google") || $0.displayName.contains("youtube") }
        await self.dataStore.removeData(ofTypes: types, for: records)
    }

    /// Cookie header + SAPISID for one request, from the live jar.
    func material() async -> AuthMaterial? {
        AuthCookies.material(from: await self.cookieStore.allCookies())
    }

    // MARK: - Persistence

    private func persist(_ jar: [HTTPCookie]) {
        guard let data = AuthCookies.archive(jar) else { return }
        self.vault.save(data)
    }

    private func startObserving() {
        guard self.observer == nil else { return }
        let observer = CookieObserver { [weak self] in self?.cookiesChanged() }
        self.observer = observer
        self.cookieStore.add(observer)
    }

    /// Google rotates `SIDCC`/`PSIDTS` regularly; keep the archive fresh, debounced.
    private func cookiesChanged() {
        guard self.state == .signedIn else { return }
        self.persistTask?.cancel()
        self.persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.state == .signedIn else { return }
            let jar = await self.cookieStore.allCookies()
            guard !Task.isCancelled, self.state == .signedIn else { return }
            if AuthCookies.material(from: jar) == nil {
                // The session cookie vanished (expired or cleared by the page).
                self.state = .signedOut
            } else {
                self.persist(jar)
            }
        }
    }
}

@MainActor
private final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func cookiesDidChange(in _: WKHTTPCookieStore) { self.onChange() }
}
