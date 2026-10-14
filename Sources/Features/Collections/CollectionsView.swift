import Observation
import SwiftUI

/// Library · Liked music · History. Signed-out users get a prompt instead of empty lists.
struct CollectionsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case library = "Library"
        case liked = "Liked music"
        case history = "History"

        var id: String { self.rawValue }
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var selection: Segment = .library
    @State private var history: BrowsePageModel?

    var body: some View {
        NavigationStack {
            Group {
                if self.environment.auth.state == .signedIn {
                    VStack(spacing: 0) {
                        Picker("Section", selection: self.$selection) {
                            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                        switch self.selection {
                        case .library: LibraryContentView()
                        case .liked: LikedMusicView()
                        case .history:
                            if let history = self.history {
                                BrowsePageView(model: history, emptyMessage: "Nothing played yet.")
                            } else {
                                ProgressView()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Your music", systemImage: "square.stack")
                    } description: {
                        Text("Sign in to see your library, liked songs and history.")
                    } actions: {
                        Button("Sign in") { self.environment.isLoginPresented = true }
                    }
                }
            }
            .navigationTitle("Collections")
            .entityDestinations()
            .toolbar { SettingsToolbarButton() }
        }
        .task(id: self.selection) {
            guard self.selection == .history, self.environment.auth.state == .signedIn else { return }
            let model = self.history ?? BrowsePageModel(type: .history, client: self.environment.client)
            self.history = model
            await model.load(force: true)
        }
    }
}

// MARK: - Library

@MainActor
@Observable
final class LibraryModel {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private(set) var content: PlaylistParser.LibraryContent?
    private(set) var phase: Phase = .loading
    private let client: YTMusicClient

    init(client: YTMusicClient) {
        self.client = client
    }

    func load() async {
        if self.content == nil { self.phase = .loading }
        do {
            self.content = try await self.client.getLibraryContent()
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = self.content == nil ? .failed(error.localizedDescription) : .loaded
        }
    }
}

struct LibraryContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: LibraryModel?

    var body: some View {
        Group {
            if let model {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(message):
                    LoadFailureView(message: message) { Task { await model.load() } }
                case .loaded:
                    if let content = model.content {
                        if content.playlists.isEmpty, content.albums.isEmpty, content.artists.isEmpty {
                            ContentUnavailableView("Your library is empty", systemImage: "music.note.list")
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 24) {
                                    if !content.playlists.isEmpty {
                                        ShelfView(title: "Playlists", entities: content.playlists.map(MediaEntity.init))
                                    }
                                    if !content.albums.isEmpty {
                                        ShelfView(title: "Albums", entities: content.albums.map(MediaEntity.init))
                                    }
                                    if !content.artists.isEmpty {
                                        ShelfView(title: "Artists", entities: content.artists.map(MediaEntity.init))
                                    }
                                }
                                .padding(.vertical)
                            }
                            .refreshable { await model.load() }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            let model = self.model ?? LibraryModel(client: self.environment.client)
            self.model = model
            await model.load()
        }
    }
}

// MARK: - Liked music

@MainActor
@Observable
final class LikedMusicModel {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    private(set) var songs: [Song] = []
    private(set) var phase: Phase = .loading
    private var token: String?
    private var isLoadingMore = false
    private let client: YTMusicClient

    init(client: YTMusicClient) {
        self.client = client
    }

    func load() async {
        if self.songs.isEmpty { self.phase = .loading }
        do {
            let response = try await self.client.getLikedSongs()
            self.songs = response.songs
            self.token = response.continuationToken
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = self.songs.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }

    func loadMoreIfNeeded(after song: Song) async {
        guard self.songs.last?.id == song.id, let token = self.token, !self.isLoadingMore else { return }
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }
        guard let more = try? await self.client.getLikedSongsContinuation(token: token) else {
            self.token = nil
            return
        }
        self.songs += more.songs
        self.token = more.continuationToken
    }
}

struct LikedMusicView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: LikedMusicModel?

    var body: some View {
        Group {
            if let model {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(message):
                    LoadFailureView(message: message) { Task { await model.load() } }
                case .loaded:
                    if model.songs.isEmpty {
                        ContentUnavailableView("No liked songs yet", systemImage: "heart")
                    } else {
                        List(model.songs) { song in
                            TrackRow(song: song) {
                                self.environment.player.play(videoId: song.videoId, playlistId: LikedMusicPlaylist.id)
                            }
                            .task { await model.loadMoreIfNeeded(after: song) }
                        }
                        .listStyle(.plain)
                        .refreshable { await model.load() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            let model = self.model ?? LikedMusicModel(client: self.environment.client)
            self.model = model
            await model.load()
        }
    }
}
