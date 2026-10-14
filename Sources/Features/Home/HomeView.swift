import Observation
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var sections: [HomeSection] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false

    private let client: YTMusicClient

    init(client: YTMusicClient) {
        self.client = client
    }

    var hasMore: Bool { self.client.hasMore(.home) }

    func load(force: Bool = false) async {
        if self.phase == .loading { return }
        if !force, self.phase == .loaded { return }
        if self.sections.isEmpty { self.phase = .loading }
        do {
            let response = try await self.client.page(.home, forceRefresh: force)
            self.sections = response.sections
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
        guard let more = try? await self.client.continuation(for: .home) else { return }
        let known = Set(self.sections.map(\.id))
        self.sections += more.filter { !known.contains($0.id) }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: HomeViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    self.content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: MediaEntity.self) { EntityPlaceholderView(entity: $0) }
            .toolbar { SettingsToolbarButton() }
        }
        .task(id: self.environment.auth.state) {
            let model = self.model ?? HomeViewModel(client: self.environment.client)
            self.model = model
            await model.load(force: true)
        }
    }

    @ViewBuilder
    private func content(_ model: HomeViewModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
        case let .failed(message):
            LoadFailureView(message: message) { Task { await model.load(force: true) } }
        case .loaded:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.sections) { section in
                        HomeShelf(section: section)
                            .task { await model.loadMoreIfNeeded(after: section) }
                    }
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical)
            }
            .refreshable { await model.load(force: true) }
        }
    }
}

private struct HomeShelf: View {
    let section: HomeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.section.title)
                .font(.title3.bold())
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(self.section.items) { item in
                        let entity = MediaEntity(item)
                        MediaActions(entity: entity) { MediaCard(entity: entity) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
