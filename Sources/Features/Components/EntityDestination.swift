import SwiftUI

extension View {
    /// Registers the screens a `MediaEntity` navigates to. Apply once per `NavigationStack`.
    func entityDestinations() -> some View {
        self.navigationDestination(for: MediaEntity.self) { entity in
            switch entity.target {
            case let .album(id), let .playlist(id):
                PlaylistDetailView(id: id, fallbackTitle: entity.title, thumbnailURL: entity.thumbnailURL)
            case let .artist(id):
                ArtistDetailView(id: id, fallbackName: entity.title)
            case let .mood(browseId, params):
                MoodCategoryView(browseId: browseId, params: params, title: entity.title)
            case .song, .unsupported:
                ContentUnavailableView(entity.title, systemImage: "music.note")
            }
        }
    }
}

/// Sections for one mood / genre.
struct MoodCategoryView: View {
    @Environment(AppEnvironment.self) private var environment

    let browseId: String
    let params: String?
    let title: String

    @State private var sections: [HomeSection] = []
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(self.sections) { section in
                            ShelfView(title: section.title, entities: section.items.map(MediaEntity.init))
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(self.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await self.load() }
    }

    private func load() async {
        self.phase = .loading
        do {
            self.sections = try await self.environment.client
                .getMoodCategory(browseId: self.browseId, params: self.params).sections
            self.phase = .loaded
        } catch is CancellationError {
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }
}
