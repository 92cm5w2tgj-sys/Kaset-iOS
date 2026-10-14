import Observation
import SwiftUI

@MainActor
@Observable
final class AddToPlaylistModel {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    let videoId: String
    private let client: YTMusicClient

    private(set) var menu: AddToPlaylistMenu?
    private(set) var phase: Phase = .loading
    /// Playlists that now contain the song (already did, or added in this sheet).
    private(set) var added: Set<String> = []
    private(set) var busyId: String?
    var message: String?

    init(videoId: String, client: YTMusicClient) {
        self.videoId = videoId
        self.client = client
    }

    func load() async {
        self.phase = .loading
        do {
            let menu = try await self.client.getAddToPlaylistOptions(videoId: self.videoId)
            self.menu = menu
            self.added = Set(menu.options.filter(\.isSelected).map(\.playlistId))
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func add(to option: AddToPlaylistOption) async {
        guard !self.added.contains(option.playlistId), self.busyId == nil else { return }
        self.busyId = option.playlistId
        defer { self.busyId = nil }
        do {
            try await self.client.addSongToPlaylist(videoId: self.videoId, playlistId: option.playlistId)
            self.added.insert(option.playlistId)
            self.message = "Added to \(option.title)"
        } catch {
            self.message = "Couldn't add: \(error.localizedDescription)"
        }
    }

    func create(title: String, privacy: PlaylistPrivacyStatus) async {
        do {
            _ = try await self.client.createPlaylist(title: title, privacyStatus: privacy, videoIds: [self.videoId])
            self.message = "Created \(title)"
            await self.load()
        } catch {
            self.message = "Couldn't create the playlist: \(error.localizedDescription)"
        }
    }
}

/// "Add to playlist": the user's playlists with a checkmark where the song already is, and a
/// way to create a new playlist that starts with this song.
struct AddToPlaylistSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let videoId: String
    let songTitle: String?

    @State private var model: AddToPlaylistModel?
    @State private var isCreating = false
    @State private var newTitle = ""
    @State private var newPrivacy: PlaylistPrivacyStatus = .private

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    self.content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { self.dismiss() } }
            }
            .overlay(alignment: .bottom) {
                if let message = self.model?.message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 16)
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            self.model?.message = nil
                        }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            let model = self.model ?? AddToPlaylistModel(videoId: self.videoId, client: self.environment.client)
            self.model = model
            await model.load()
        }
        .alert("New Playlist", isPresented: self.$isCreating) {
            TextField("Title", text: self.$newTitle)
            Button("Create") {
                let title = self.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                self.newTitle = ""
                guard !title.isEmpty, let model else { return }
                Task { await model.create(title: title, privacy: self.newPrivacy) }
            }
            Button("Cancel", role: .cancel) { self.newTitle = "" }
        } message: {
            Text("The playlist starts with \(self.songTitle ?? "this song").")
        }
    }

    @ViewBuilder
    private func content(_ model: AddToPlaylistModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            LoadFailureView(message: message) { Task { await model.load() } }
        case .loaded:
            List {
                Section {
                    Button {
                        self.isCreating = true
                    } label: {
                        Label("New Playlist", systemImage: "plus.circle.fill")
                    }
                    Picker("Privacy", selection: self.$newPrivacy) {
                        Text("Private").tag(PlaylistPrivacyStatus.private)
                        Text("Unlisted").tag(PlaylistPrivacyStatus.unlisted)
                        Text("Public").tag(PlaylistPrivacyStatus.public)
                    }
                    .pickerStyle(.menu)
                }
                Section("Your playlists") {
                    ForEach(model.menu?.options ?? []) { option in
                        Button {
                            Task { await model.add(to: option) }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(url: option.thumbnailURL)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).foregroundStyle(.primary).lineLimit(1)
                                    if let subtitle = option.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if model.busyId == option.playlistId {
                                    ProgressView()
                                } else if model.added.contains(option.playlistId) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                                }
                            }
                        }
                        .disabled(model.added.contains(option.playlistId))
                    }
                }
            }
        }
    }
}

extension View {
    /// Presents the add-to-playlist sheet for a song.
    func addToPlaylistSheet(isPresented: Binding<Bool>, videoId: String, title: String?) -> some View {
        self.sheet(isPresented: isPresented) {
            AddToPlaylistSheet(videoId: videoId, songTitle: title)
        }
    }
}
