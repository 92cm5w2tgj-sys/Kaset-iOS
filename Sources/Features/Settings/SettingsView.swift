import SwiftUI

/// Minimal until K10: account state, sign out, diagnostics entry points.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var environment = self.environment

        NavigationStack {
            Form {
                Section("Account") {
                    switch self.environment.auth.state {
                    case .signedIn:
                        Label("Signed in", systemImage: "checkmark.seal.fill")
                        Button("Sign out", role: .destructive) {
                            Task {
                                await self.environment.signOut()
                                self.dismiss()
                            }
                        }
                    case .signedOut:
                        Button("Sign in") {
                            self.dismiss()
                            self.environment.isLoginPresented = true
                        }
                    case .unknown:
                        ProgressView()
                    }
                }
                Section("Diagnostics") {
                    NavigationLink("Playback debug") { PlaybackDebugView(player: self.environment.player) }
                    NavigationLink("API debug") { APIDebugView(client: self.environment.client, player: self.environment.player) }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { self.dismiss() } }
            }
        }
    }
}
