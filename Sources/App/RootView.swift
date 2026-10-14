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
            Button("Debug lab") { environment.isLabPresented = true }
                .buttonStyle(.borderedProminent)
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
        .fullScreenCover(isPresented: $environment.isLabPresented) {
            DebugLabView(model: environment.lab)
                .overlay(alignment: .topTrailing) {
                    Button("Fermer") { environment.isLabPresented = false }
                        .font(.footnote)
                        .padding(8)
                }
        }
    }
}
