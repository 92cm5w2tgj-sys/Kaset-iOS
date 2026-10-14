import Observation
import SwiftUI

/// One paginated browse surface (Home, Explore, Charts, Moods, New releases, History).
@MainActor
@Observable
final class BrowsePageModel {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    let type: PaginatedContentType
    private(set) var sections: [HomeSection] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false

    private let client: YTMusicClient

    init(type: PaginatedContentType, client: YTMusicClient) {
        self.type = type
        self.client = client
    }

    var hasMore: Bool { self.client.hasMore(self.type) }

    /// Browse ids of the shortcut buttons YouTube Music puts on its Explore page. They point at
    /// surfaces that already are Discover segments, so they are dropped here.
    private static let shortcutBrowseIds: Set<String> = [
        "FEmusic_moods_and_genres", "FEmusic_charts", "FEmusic_new_releases", "FEmusic_explore",
    ]

    /// Explore repeats the chart shelves that already have their own Discover segment.
    private func filtered(_ sections: [HomeSection]) -> [HomeSection] {
        Self.withoutShortcuts(sections, dropsCharts: self.type == .explore)
    }

    private static func withoutShortcuts(_ sections: [HomeSection], dropsCharts: Bool) -> [HomeSection] {
        sections.compactMap { section in
            if dropsCharts, section.isChart { return nil }
            let items = section.items.filter { item in
                guard case let .playlist(playlist) = item else { return true }
                let browseId = playlist.resolvedMoodCategoryEndpoint?.browseId ?? playlist.id
                return !Self.shortcutBrowseIds.contains(browseId)
            }
            guard !items.isEmpty else { return nil }
            return items.count == section.items.count
                ? section
                : HomeSection(id: section.id, title: section.title, items: items, isChart: section.isChart)
        }
    }

    func load(force: Bool = false) async {
        if self.phase == .loading { return }
        if !force, self.phase == .loaded { return }
        if self.sections.isEmpty { self.phase = .loading }
        do {
            let response = try await self.client.page(self.type, forceRefresh: force)
            self.sections = self.filtered(response.sections)
            self.phase = .loaded
        } catch is CancellationError {
            if self.sections.isEmpty { self.phase = .idle }
        } catch {
            self.phase = self.sections.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }

    func loadMoreIfNeeded(after section: HomeSection) async {
        guard self.sections.last?.id == section.id, self.hasMore, !self.isLoadingMore else { return }
        self.isLoadingMore = true
        defer { self.isLoadingMore = false }
        guard let more = try? await self.client.continuation(for: self.type) else { return }
        let known = Set(self.sections.map(\.id))
        self.sections += self.filtered(more.filter { !known.contains($0.id) })
    }
}

/// Shelves for a `BrowsePageModel`; songs-only sections render as a list-like grid of cards.
struct BrowsePageView: View {
    let model: BrowsePageModel
    var emptyMessage = "Nothing here yet."

    var body: some View {
        switch self.model.phase {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            LoadFailureView(message: message) { Task { await self.model.load(force: true) } }
        case .loaded:
            if self.model.sections.isEmpty {
                ContentUnavailableView(self.emptyMessage, systemImage: "tray")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(self.model.sections) { section in
                            ShelfView(title: section.title, entities: section.items.map(MediaEntity.init))
                                .task { await self.model.loadMoreIfNeeded(after: section) }
                        }
                        if self.model.isLoadingMore {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable { await self.model.load(force: true) }
            }
        }
    }
}

/// Titled horizontal shelf. Mood entries render as compact chips instead of artwork cards.
struct ShelfView: View {
    let title: String
    let entities: [MediaEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !self.title.isEmpty {
                Text(self.title)
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(self.entities) { entity in
                        MediaActions(entity: entity) {
                            if case .mood = entity.target {
                                Text(entity.title)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            } else {
                                MediaCard(entity: entity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}
