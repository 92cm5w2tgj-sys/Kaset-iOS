import SwiftUI

/// K3 verification screen: live Home sections and Search results through `YTMusicClient`.
/// Removed once the real Home/Search screens land (K6).
struct APIDebugView: View {
    let client: YTMusicClient

    @State private var sections: [HomeSection] = []
    @State private var results: [SearchResultItem] = []
    @State private var suggestions: [SearchSuggestion] = []
    @State private var query = ""
    @State private var status = "…"

    var body: some View {
        NavigationStack {
            List {
                Section("Statut") { Text(self.status).font(.footnote) }

                if !self.suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(self.suggestions) { Text($0.query) }
                    }
                }

                if !self.results.isEmpty {
                    Section("Résultats (\(self.results.count))") {
                        ForEach(self.results) { item in
                            VStack(alignment: .leading) {
                                Text(item.title)
                                if let subtitle = item.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                ForEach(self.sections) { section in
                    Section("\(section.title) (\(section.items.count))") {
                        ForEach(section.items) { Text($0.title) }
                    }
                }
            }
            .navigationTitle("API debug")
            .searchable(text: self.$query)
            .onSubmit(of: .search) { Task { await self.search() } }
            .task(id: self.query) { await self.loadSuggestions() }
            .refreshable { await self.loadHome(force: true) }
            .task { await self.loadHome(force: false) }
        }
    }

    private func loadHome(force: Bool) async {
        do {
            let response = try await self.client.getHome(forceRefresh: force)
            self.sections = response.sections
            self.status = "Home : \(response.sections.count) sections, suite : \(self.client.hasMore(.home))"
        } catch {
            self.status = "Home : \(error.localizedDescription)"
        }
    }

    private func search() async {
        do {
            let response = try await self.client.search(query: self.query)
            self.results = response.allItems
            self.suggestions = []
            self.status = "Recherche « \(self.query) » : \(response.allItems.count) résultats"
        } catch {
            self.status = "Recherche : \(error.localizedDescription)"
        }
    }

    private func loadSuggestions() async {
        guard !self.query.isEmpty else { self.suggestions = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        self.suggestions = (try? await self.client.getSearchSuggestions(query: self.query)) ?? []
    }
}
