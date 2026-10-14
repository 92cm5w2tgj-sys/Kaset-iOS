import Observation

/// Owns the long-lived services.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthStore
    let client: YTMusicClient
    let player: WebPlayer

    var isPlaybackDebugPresented = false
    var isAPIDebugPresented = false
    var isLoginPresented = false

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.client = YTMusicClient(auth: auth)
        self.player = WebPlayer()
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
        self.client.resetSessionState()
        self.player.reload()
    }
}
