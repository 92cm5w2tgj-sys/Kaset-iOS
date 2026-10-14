import Observation
import SwiftUI

@MainActor
@Observable
final class PlaylistDetailModel {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    let id: String
    private let client: YTMusicClient

    private(set) var detail: PlaylistDetail?
    private(set) var tracks: [Song] = []
    private(set) var phase: Phase = .loading
    private var continuationToken: String?
    private(set) var isLoadingMore = false

    init(id: String, client: YTMusicClient) {
        self.id = id
        self.client = client
    }

    /// Id usable in `watch?list=`: albums expose their `OLAK…` audio playlist as library target.
    var watchListId: String? {
        guard let detail else { return nil }
        if let target = detail.libraryTargetId, !target.isEmpty { return MediaEntity.watchPlaylistId(target) }
        if detail.isAlbum { return nil }
        return MediaEntity.watchPlaylistId(detail.id)
    }

    func load() async {
        self.phase = .loading
        do {
            let response = try await self.client.getPlaylist(id: self.id)
            self.detail = response.detail
            self.tracks = response.detail.tracks
            self.continuationToken = response.continuationToken
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(after song: Song) async {
        guard self.tracks.last?.id == song.id, let token = self.continuationToken, !self.isLoadingMore else { return }
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }
        let requiresAuth = self.detail?.requiresPersonalAccountForContinuations ?? false
        guard let more = try? await self.client.getPlaylistContinuation(token: token, requiresAuth: requiresAuth) else {
            self.continuationToken = nil
            return
        }
        self.tracks += more.tracks
        self.continuationToken = more.continuationToken
    }
}

/// Playlist or album: header, play / shuffle, tracks. Every action is a web player command.
struct PlaylistDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: PlaylistDetailModel?

    let id: String
    var fallbackTitle: String = ""
    var thumbnailURL: URL?

    var body: some View {
        Group {
            if let model {
                self.content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(self.fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.model == nil { self.model = PlaylistDetailModel(id: self.id, client: self.environment.client) }
            if self.model?.detail == nil { await self.model?.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: PlaylistDetailModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            LoadFailureView(message: message) { Task { await model.load() } }
        case .loaded:
            List {
                if let detail = model.detail {
                    Section { self.header(detail, model: model) }
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, index: index + 1, showsArtwork: model.detail?.isAlbum != true) {
                            self.play(song, model: model)
                        }
                        .task { await model.loadMoreIfNeeded(after: song) }
                    }
                    if model.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func header(_ detail: PlaylistDetail, model: PlaylistDetailModel) -> some View {
        VStack(spacing: 12) {
            ArtworkView(url: detail.thumbnailURL ?? self.thumbnailURL)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(detail.title).font(.title2.bold()).multilineTextAlignment(.center)
            if let author = detail.author?.name {
                Text(author).foregroundStyle(.secondary)
            }
            Text(detail.trackCountDisplay).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { self.playAll(model: model, shuffled: false) } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { self.playAll(model: model, shuffled: true) } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 24) {
                if detail.supportsLibraryToggle {
                    Menu("Library", systemImage: "plus") {
                        Button("Add to Library", systemImage: "plus") {
                            Task { try? await self.environment.client.addPlaylistToLibrary(id: detail.libraryTargetId ?? detail.id) }
                        }
                        Button("Remove from Library", systemImage: "minus", role: .destructive) {
                            Task { try? await self.environment.client.removePlaylistFromLibrary(id: detail.libraryTargetId ?? detail.id) }
                        }
                    }
                }
                if let url = URL(string: "https://music.youtube.com/playlist?list=\(model.watchListId ?? MediaEntity.watchPlaylistId(detail.id))") {
                    ShareLink(item: url)
                }
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
    }

    private func playAll(model: PlaylistDetailModel, shuffled: Bool) {
        let player = self.environment.player
        let first = model.tracks.first(where: \.isPlayable)?.videoId
        if let list = model.watchListId {
            if shuffled {
                player.playShuffled(videoId: nil, playlistId: list)
            } else {
                player.play(videoId: first, playlistId: list)
            }
        } else if let first {
            player.play(videoId: first, playlistId: "RDAMVM\(first)")
        }
    }

    private func play(_ song: Song, model: PlaylistDetailModel) {
        let list = model.watchListId ?? "RDAMVM\(song.videoId)"
        self.environment.player.play(videoId: song.videoId, playlistId: list)
    }
}

/// A song in a list: tap plays, long press offers play next / add to queue / like.
struct TrackRow: View {
    @Environment(AppEnvironment.self) private var environment

    let song: Song
    var index: Int?
    var showsArtwork = true
    let onPlay: () -> Void

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 12) {
                if self.showsArtwork {
                    ArtworkView(url: self.song.thumbnailURL)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let index {
                    Text("\(index)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.song.title).lineLimit(1)
                    if !self.song.artistsDisplay.isEmpty {
                        Text(self.song.artistsDisplay).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let duration = self.song.duration {
                    Text(Self.format(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!self.song.isPlayable)
        .contextMenu {
            Button("Play Next", systemImage: "text.insert") { self.environment.player.playNext(videoId: self.song.videoId) }
            Button("Add to Queue", systemImage: "text.append") { self.environment.player.addToQueue(videoId: self.song.videoId) }
            Button("Like", systemImage: "heart") {
                Task { try? await self.environment.client.rateSong(videoId: self.song.videoId, rating: .like) }
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
