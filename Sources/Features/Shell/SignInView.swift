import SwiftUI

struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isSettingsPresented = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Kaset").font(.largeTitle.bold())
            Text("Sign in with your Google account to play your music.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Sign in") { self.environment.isLoginPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Diagnostics") { self.isSettingsPresented = true }
                .font(.footnote)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: self.$isSettingsPresented) { SettingsView() }
    }
}
