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
        .navigationTitle(self.model?.detail?.title ?? self.fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { self.detailToolbar }
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
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
    }

    private func header(_ detail: PlaylistDetail, model: PlaylistDetailModel) -> some View {
        VStack(spacing: 14) {
            ArtworkView(url: detail.thumbnailURL ?? self.thumbnailURL)
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                .padding(.top, 8)

            // The title lives in the navigation bar only; this is just the byline.
            Text(Self.byline(for: detail))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button { self.playAll(model: model, shuffled: false) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                Button { self.playAll(model: model, shuffled: true) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func byline(for detail: PlaylistDetail) -> String {
        let author = detail.author?.name
            .replacingOccurrences(of: "Playlist • ", with: "")
            .trimmingCharacters(in: .whitespaces)
        return [author, detail.trackCountDisplay].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Library and share live in the navigation bar, like the system apps.
    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if let detail = self.model?.detail {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if detail.supportsLibraryToggle {
                        Button("Add to Library", systemImage: "plus") {
                            Task { try? await self.environment.client.addPlaylistToLibrary(id: detail.libraryTargetId ?? detail.id) }
                        }
                        Button("Remove from Library", systemImage: "minus", role: .destructive) {
                            Task { try? await self.environment.client.removePlaylistFromLibrary(id: detail.libraryTargetId ?? detail.id) }
                        }
                    }
                    if let url = URL(string: "https://music.youtube.com/playlist?list=\(self.model?.watchListId ?? MediaEntity.watchPlaylistId(detail.id))") {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .neutralMenuTint()
                .accessibilityLabel("More")
            }
        }
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

    /// This row is the track the web player is on (not an ad, not another occurrence of a
    /// different song).
    private var isCurrent: Bool {
        self.environment.player.state.videoId == self.song.videoId
    }

    private var isPlaying: Bool {
        self.isCurrent && self.environment.player.state.isPlaying
    }

    var body: some View {
        Button(action: self.onPlay) {
            HStack(spacing: 12) {
                if self.showsArtwork {
                    ArtworkView(url: self.song.thumbnailURL)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            if self.isCurrent {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.black.opacity(0.45))
                                EqualizerView(isAnimating: self.isPlaying, color: .white)
                                    .frame(width: 18, height: 16)
                            }
                        }
                } else {
                    Group {
                        if self.isCurrent {
                            EqualizerView(isAnimating: self.isPlaying)
                                .frame(width: 18, height: 16)
                        } else if let index {
                            Text("\(index)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.song.title)
                        .font(.body)
                        .foregroundStyle(self.isCurrent ? Color.brand : Color.primary)
                        .lineLimit(1)
                    if !self.song.artistsDisplay.isEmpty {
                        Text(self.song.artistsDisplay).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let duration = self.song.duration {
                    Text(Self.format(duration)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Menu {
                    self.menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .neutralMenuTint()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!self.song.isPlayable)
        .neutralMenuTint()
        .contextMenu { self.menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Play Next", systemImage: "text.insert") { self.environment.player.playNext(videoId: self.song.videoId) }
        Button("Add to Queue", systemImage: "text.append") { self.environment.player.addToQueue(videoId: self.song.videoId) }
        if self.environment.auth.state == .signedIn {
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
