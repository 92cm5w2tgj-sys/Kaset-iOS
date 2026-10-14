import SwiftUI

/// Explore · Charts · Moods · New releases. Every segment keeps its own model and scroll
/// position: segments are loaded the first time they are shown and then only hidden.
struct DiscoverView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case explore = "Explore"
        case charts = "Charts"
        case moods = "Moods"
        case newReleases = "New"

        var id: String { self.rawValue }

        var type: PaginatedContentType {
            switch self {
            case .explore: .explore
            case .charts: .charts
            case .moods: .moodsAndGenres
            case .newReleases: .newReleases
            }
        }
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var selection: Segment = .explore
    @State private var models: [Segment: BrowsePageModel] = [:]
    @State private var visited: Set<Segment> = [.explore]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: self.$selection) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                ZStack {
                    ForEach(Segment.allCases) { segment in
                        if self.visited.contains(segment), let model = self.models[segment] {
                            BrowsePageView(model: model)
                                .opacity(self.selection == segment ? 1 : 0)
                                .allowsHitTesting(self.selection == segment)
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .entityDestinations()
            .toolbar { SettingsToolbarButton() }
        }
        .task(id: self.selection) {
            self.visited.insert(self.selection)
            if self.models[self.selection] == nil {
                self.models[self.selection] = BrowsePageModel(type: self.selection.type, client: self.environment.client)
            }
            await self.models[self.selection]?.load()
        }
    }
}
