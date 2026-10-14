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
                    LazyVStack(alignment: .leading, spacing: 24) {
                        self.header(detail, model: model)
                        if !detail.songs.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.songsSectionTitle ?? "Songs").font(.title2.weight(.bold)).padding(.horizontal, 20)
                                ForEach(detail.songs.prefix(10)) { song in
                                    TrackRow(song: song) {
                                        self.environment.player.play(videoId: song.videoId, playlistId: "RDAMVM\(song.videoId)")
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        ForEach(detail.orderedSections) { section in
                            ShelfView(title: section.title, entities: Self.entities(of: section))
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }

    private func header(_ detail: ArtistDetail, model: ArtistDetailModel) -> some View {
        VStack(spacing: 10) {
            ArtworkView(url: detail.thumbnailURL ?? detail.artist.thumbnailURL)
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.top, 8)
            Text(detail.artist.name).font(.largeTitle.weight(.bold))
            if let audience = detail.monthlyAudience {
                Text(audience).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let mix = detail.mixPlaylistId {
                    Button {
                        self.environment.player.play(videoId: detail.mixVideoId, playlistId: mix)
                    } label: {
                        Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(TintedActionButtonStyle())
                } else if let first = detail.songs.first {
                    Button {
                        self.environment.player.play(videoId: first.videoId, playlistId: "RDAMVM\(first.videoId)")
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(TintedActionButtonStyle())
                }
                if detail.channelId != nil {
                    Button(model.isSubscribed ? "Following" : "Follow") {
                        Task { await model.toggleSubscription() }
                    }
                    .buttonStyle(TintedActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private static func entities(of section: ArtistDetailSection) -> [MediaEntity] {
        switch section.content {
        case let .albums(albums): albums.map(MediaEntity.init)
        case let .playlists(playlists): playlists.map(MediaEntity.init)
        case let .artists(artists): artists.map(MediaEntity.init)
        }
    }
}
