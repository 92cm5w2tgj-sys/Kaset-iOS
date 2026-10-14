import Observation
import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var query = ""
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: [SearchResultItem] = []
    private(set) var phase: Phase = .idle
    private(set) var submittedQuery = ""

    private let client: YTMusicClient

    init(client: YTMusicClient) {
        self.client = client
    }

    func updateSuggestions() async {
        let text = self.query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            self.suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        self.suggestions = (try? await self.client.getSearchSuggestions(query: text)) ?? []
    }

    func submit(_ text: String? = nil) async {
        let text = (text ?? self.query).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        self.query = text
        self.submittedQuery = text
        self.suggestions = []
        self.phase = .loading
        do {
            self.results = try await self.client.search(query: text).allItems
            self.phase = .loaded
        } catch is CancellationError {
            self.phase = .idle
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    /// Results grouped for display; the server order is kept inside each group.
    var groups: [(title: String, items: [MediaEntity])] {
        var songs: [MediaEntity] = [], videos: [MediaEntity] = [], albums: [MediaEntity] = []
        var artists: [MediaEntity] = [], playlists: [MediaEntity] = []
        for item in self.results {
            let entity = MediaEntity(item)
            switch item {
            case .song: songs.append(entity)
            case .video: videos.append(entity)
            case .album, .audiobook: albums.append(entity)
            case .artist, .profile: artists.append(entity)
            case .playlist: playlists.append(entity)
            case .podcastShow, .podcastEpisode: break
            }
        }
        return [("Songs", songs), ("Artists", artists), ("Albums", albums), ("Playlists", playlists), ("Videos", videos)]
            .filter { !$0.1.isEmpty }
    }
}

struct SearchView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: SearchViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    self.content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: MediaEntity.self) { EntityPlaceholderView(entity: $0) }
            .toolbar { SettingsToolbarButton() }
        }
        .task {
            if self.model == nil { self.model = SearchViewModel(client: self.environment.client) }
        }
    }

    @ViewBuilder
    private func content(_ model: SearchViewModel) -> some View {
        @Bindable var model = model

        Group {
            switch model.phase {
            case .idle:
                ContentUnavailableView("Search YouTube Music", systemImage: "magnifyingglass",
                                       description: Text("Songs, albums, artists and playlists."))
            case .loading:
                ProgressView()
            case let .failed(message):
                LoadFailureView(message: message) { Task { await model.submit(model.submittedQuery) } }
            case .loaded:
                if model.groups.isEmpty {
                    ContentUnavailableView.search(text: model.submittedQuery)
                } else {
                    List {
                        ForEach(model.groups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.items) { entity in
                                    MediaActions(entity: entity) { MediaRow(entity: entity) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .searchable(text: $model.query, prompt: "Songs, albums, artists")
        .searchSuggestions {
            ForEach(model.suggestions) { suggestion in
                Text(suggestion.query).searchCompletion(suggestion.query)
            }
        }
        .onSubmit(of: .search) { Task { await model.submit() } }
        .task(id: model.query) { await model.updateSuggestions() }
    }
}
