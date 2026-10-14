import SwiftUI

/// Account, playback and content preferences, plus diagnostics entry points.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PlaybackAudioQuality.storageKey) private var audioQuality = PlaybackAudioQuality.auto.rawValue
    @AppStorage(ContentLanguage.storageKey) private var language = ContentLanguage.system.rawValue
    @AppStorage(Haptics.storageKey) private var haptics = true
    @AppStorage("nativeNowPlaying") private var nativeNowPlaying = true
    @AppStorage(AdSkip.storageKey) private var adAutoSkip = false

    @State private var accounts: [UserAccount] = []
    @State private var isSwitching = false

    var body: some View {
        NavigationStack {
            Form {
                self.accountSection

                Section {
                    Picker("Audio quality", selection: self.$audioQuality) {
                        ForEach(PlaybackAudioQuality.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    .onChange(of: self.audioQuality) { _, _ in self.environment.player.applyAudioQuality() }
                    Toggle("Haptic feedback", isOn: self.$haptics)
                    Toggle("Skip ads automatically", isOn: self.$adAutoSkip)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Skipping ads is an opt-in and may go against YouTube's terms of service.")
                }
                .onChange(of: self.adAutoSkip) { _, _ in self.environment.player.applyAdSkipSetting() }

                Section {
                    Picker("Content language", selection: self.$language) {
                        ForEach(ContentLanguage.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    .onChange(of: self.language) { _, _ in
                        self.environment.client.resetSessionState()
                    }
                } footer: {
                    Text("Changes the language of titles and shelves returned by YouTube Music.")
                }

                Section("Diagnostics") {
                    Toggle("Native Now Playing card", isOn: self.$nativeNowPlaying)
                    Button("Inspect queue (log)") { self.environment.player.inspectQueue() }
                    NavigationLink("Playback debug") { PlaybackDebugView(player: self.environment.player) }
                    NavigationLink("API debug") { APIDebugView(client: self.environment.client, player: self.environment.player) }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { self.dismiss() } }
            }
            .task(id: self.environment.auth.state) { await self.loadAccounts() }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            switch self.environment.auth.state {
            case .signedIn:
                ForEach(self.accounts) { account in
                    Button {
                        guard !account.isSelected else { return }
                        Task {
                            self.isSwitching = true
                            await self.environment.switchAccount(to: account)
                            self.isSwitching = false
                            await self.loadAccounts()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                if let handle = account.handle {
                                    Text(handle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if account.isSelected { Image(systemName: "checkmark") }
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(self.isSwitching)
                }
                if self.accounts.isEmpty {
                    Label("Signed in", systemImage: "checkmark.seal.fill")
                }
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
    }

    private func loadAccounts() async {
        guard self.environment.auth.state == .signedIn else {
            self.accounts = []
            return
        }
        self.accounts = (try? await self.environment.client.fetchAccountsList().accounts) ?? []
    }
}
