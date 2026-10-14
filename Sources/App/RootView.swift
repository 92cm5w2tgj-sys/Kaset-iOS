import SwiftUI

/// Launch routing: unknown → splash, signed out → sign-in, signed in → tabs. The player's web
/// view stays attached to the window as a hidden 1×1 view for the whole app lifetime so audio
/// keeps running.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = self.environment

        Group {
            switch environment.auth.state {
            case .unknown:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabView()
            }
        }
        .background(alignment: .topLeading) {
            WebViewHost(webView: environment.player.webView)
                .id(environment.player.generation)
                // A phone-sized (but invisible) page: at 1×1 the web app lays out as a tiny
                // viewport and its queue/player-bar DOM is not reliably populated.
                .frame(width: 390, height: 844)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .task { await environment.start() }
        .sheet(isPresented: $environment.isLoginPresented) {
            LoginView { Task { await environment.loginFinished() } }
        }
    }
}
