import Observation
import SwiftUI

@MainActor
@Observable
final class ArtistDetailModel {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    let id: String
    private let client: YTMusicClient
    private(set) var detail: ArtistDetail?
    private(set) var phase: Phase = .loading
    var isSubscribed = false

    init(id: String, client: YTMusicClient) {
        self.id = id
        self.client = client
    }

    func load() async {
        self.phase = .loading
        do {
            let detail = try await self.client.getArtist(id: self.id)
            self.detail = detail
            self.isSubscribed = detail.isSubscribed
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    func toggleSubscription() async {
        guard let channelId = self.detail?.channelId else { return }
        let target = !self.isSubscribed
        self.isSubscribed = target
        do {
            if target {
                try await self.client.subscribeToArtist(channelId: channelId)
            } else {
                try await self.client.unsubscribeFromArtist(channelId: channelId)
            }
        } catch {
            self.isSubscribed = !target
        }
    }
}

struct ArtistDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: ArtistDetailModel?
    @State private var isAboutExpanded = false

    let id: String
    var fallbackName: String = ""

    var body: some View {
        Group {
            if let model {
                self.content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(self.fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if self.model == nil { self.model = ArtistDetailModel(id: self.id, client: self.environment.client) }
            if self.model?.detail == nil { await self.model?.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: ArtistDetailModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            LoadFailureView(message: message) { Task { await model.load() } }
        case .loaded:
            if let detail = model.detail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        self.header(detail, model: model)
                        self.topSongs(detail)
                        if detail.orderedSections.isEmpty {
                            // Same fallback as kaset: when the page has no ordered sections the
                            // typed collections are shown in a fixed order.
                            self.shelf("Albums", detail.albums.map(MediaEntity.init))
                            self.shelf("Singles & EPs", detail.singles.map(MediaEntity.init))
                            self.shelf("Playlists", detail.playlistsByArtist.map(MediaEntity.init))
                            self.shelf("Fans might also like", detail.relatedArtists.map(MediaEntity.init))
                        } else {
                            ForEach(detail.orderedSections) { section in
                                self.shelf(section.title, Self.entities(of: section))
                            }
                        }
                        self.about(detail)
                    }
                    .padding(.vertical)
                }
            }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ entities: [MediaEntity]) -> some View {
        if !entities.isEmpty { ShelfView(title: title, entities: entities) }
    }

    private func header(_ detail: ArtistDetail, model: ArtistDetailModel) -> some View {
        VStack(spacing: 10) {
            ArtworkView(url: detail.thumbnailURL ?? detail.artist.thumbnailURL)
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.top, 8)
            Text(detail.profileKind == .profile ? "PROFILE" : "ARTIST")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(detail.artist.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            if let audience = detail.monthlyAudience {
                Text(audience).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if detail.profileKind == .artist, let seed = detail.mixPlaylistId ?? detail.songs.first.map({ "RDAMVM\($0.videoId)" }) {
                    Button {
                        self.environment.player.playShuffled(videoId: nil, playlistId: seed)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TintedActionButtonStyle())
                }
                if let mix = detail.mixPlaylistId {
                    Button {
                        self.environment.player.play(videoId: detail.mixVideoId, playlistId: mix)
                    } label: {
                        Label("Mix", systemImage: "play.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TintedActionButtonStyle())
                }
            }
            if detail.channelId != nil, self.environment.auth.state == .signedIn {
                Button {
                    Task { await model.toggleSubscription() }
                } label: {
                    Text(model.isSubscribed
                        ? (detail.subscribedButtonText ?? "Following")
                        : (detail.unsubscribedButtonText ?? "Follow"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TintedActionButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func topSongs(_ detail: ArtistDetail) -> some View {
        if !detail.songs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(detail.songsSectionTitle ?? "Top songs")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if detail.hasMoreSongs, let browseId = detail.songsBrowseId {
                        NavigationLink("See all") {
                            ArtistSongsView(
                                browseId: browseId, params: detail.songsParams,
                                title: detail.songsSectionTitle ?? "Top songs"
                            )
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, 20)
                ForEach(detail.songs.prefix(5)) { song in
                    TrackRow(song: song) {
                        self.environment.player.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    @ViewBuilder
    private func about(_ detail: ArtistDetail) -> some View {
        if let description = detail.description, !description.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("About").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(self.isAboutExpanded ? nil : 4)
                Button(self.isAboutExpanded ? "Less" : "More") {
                    withAnimation { self.isAboutExpanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 20)
        }
    }

    private static func entities(of section: ArtistDetailSection) -> [MediaEntity] {
        switch section.content {
        case let .albums(albums): albums.map(MediaEntity.init)
        case let .playlists(playlists): playlists.map(MediaEntity.init)
        case let .artists(artists): artists.map(MediaEntity.init)
        }
    }
}

/// Everything by an artist, behind "See all" on the top songs shelf.
struct ArtistSongsView: View {
    @Environment(AppEnvironment.self) private var environment

    let browseId: String
    let params: String?
    let title: String

    @State private var songs: [Song] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    var body: some View {
        Group {
            switch self.phase {
            case .loading:
                ProgressView()
            case let .failed(message):
                LoadFailureView(message: message) { Task { await self.load() } }
            case .loaded:
                List(self.songs) { song in
                    TrackRow(song: song) {
                        self.environment.player.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(self.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.load() }
    }

    private func load() async {
        self.phase = .loading
        do {
            self.songs = try await self.environment.client.getArtistSongs(browseId: self.browseId, params: self.params)
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }
}
