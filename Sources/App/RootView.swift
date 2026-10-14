import SwiftUI

/// Minimal root until the app shell lands (K5). While the debug lab is closed, the lab's
/// web view stays attached to the window as a 1×1 hidden view so audio keeps running.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = self.environment

        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
            Text("Kaset")
                .font(.largeTitle.bold())
            self.accountRow
            Button("Debug lab") { environment.isLabPresented = true }
                .buttonStyle(.borderedProminent)
            Button("API debug") { environment.isAPIDebugPresented = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .topLeading) {
            if !environment.isLabPresented {
                WebViewHost(webView: environment.lab.webView)
                    .id(environment.lab.generation)
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .task { await environment.start() }
        .sheet(isPresented: $environment.isLoginPresented) {
            LoginView { Task { await environment.loginFinished() } }
        }
        .sheet(isPresented: $environment.isAPIDebugPresented) {
            APIDebugView(client: environment.client)
        }
        .fullScreenCover(isPresented: $environment.isLabPresented) {
            DebugLabView(model: environment.lab)
                .overlay(alignment: .topTrailing) {
                    Button("Fermer") { environment.isLabPresented = false }
                        .font(.footnote)
                        .padding(8)
                }
        }
    }

    @ViewBuilder
    private var accountRow: some View {
        switch self.environment.auth.state {
        case .unknown:
            ProgressView()
        case .signedOut:
            Button("Se connecter") { self.environment.isLoginPresented = true }
        case .signedIn:
            VStack(spacing: 4) {
                Label("Connecté", systemImage: "checkmark.seal.fill")
                Button("Se déconnecter", role: .destructive) {
                    Task { await self.environment.signOut() }
                }
            }
        }
    }
}
