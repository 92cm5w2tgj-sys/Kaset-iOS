import Foundation
import Observation

/// Owns the long-lived services.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthStore
    let client: YTMusicClient
    let player: WebPlayer
    private let accountSwitcher = AccountSwitcher()

    var isPlaybackDebugPresented = false
    var isLoginPresented = false

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.client = YTMusicClient(auth: auth)
        self.player = WebPlayer()
        self.client.brandIdProvider = { AccountSwitcher.storedBrandId }
    }

    /// Switches personal/brand identity: web session first, then API scope, then the player.
    func switchAccount(to account: UserAccount) async {
        await self.accountSwitcher.switchSession(to: account)
        self.client.resetSessionState()
        self.player.reload()
    }

    /// Launch work: put the archived session back, and reload the web view if it was missing.
    func start() async {
        if await self.auth.restore() {
            self.player.reload()
        }
    }

    func loginFinished() async {
        if await self.auth.loginFinished() {
            self.isLoginPresented = false
            self.player.reload()
        }
    }

    func signOut() async {
        await self.auth.signOut()
        UserDefaults.standard.removeObject(forKey: AccountSwitcher.brandIdKey)
        self.client.resetSessionState()
        self.player.reload()
    }
}
