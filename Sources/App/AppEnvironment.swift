import Observation

/// Owns the long-lived services. Later steps add the API client and `WebPlayer`.
@MainActor
@Observable
final class AppEnvironment {
    /// The spike's player, kept alive for the whole app lifetime so playback survives
    /// navigating away from the debug lab. Replaced by `WebPlayer` in K4.
    let lab = PlayerModel()
    let auth: AuthStore
    let client: YTMusicClient

    var isLabPresented = false
    var isAPIDebugPresented = false
    var isLoginPresented = false

    init() {
        let auth = AuthStore()
        self.auth = auth
        self.client = YTMusicClient(auth: auth)
    }

    /// Launch work: put the archived session back, and reload the web view if it was missing.
    func start() async {
        if await self.auth.restore() {
            self.lab.reload()
        }
    }

    func loginFinished() async {
        if await self.auth.loginFinished() {
            self.isLoginPresented = false
            self.lab.reload()
        }
    }

    func signOut() async {
        await self.auth.signOut()
        self.client.resetSessionState()
        self.lab.reload()
    }
}
