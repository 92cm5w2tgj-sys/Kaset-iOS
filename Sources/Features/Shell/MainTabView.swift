import SwiftUI

/// Apple Music-style shell: Home · Discover · Collections · Search, with the mini player as the
/// tab bar's bottom accessory (full pill, or compact inline when the bar minimizes).
struct MainTabView: View {
    enum Tab: Hashable {
        case home, discover, collections, search
    }

    @Environment(AppEnvironment.self) private var environment
    @Namespace private var nowPlayingNamespace
    @State private var selection: Tab = .home
    @State private var isNowPlayingPresented = false

    var body: some View {
        TabView(selection: self.$selection) {
            SwiftUI.Tab("Home", systemImage: "house", value: Tab.home) {
                HomeView()
            }
            SwiftUI.Tab("Discover", systemImage: "sparkles", value: Tab.discover) {
                self.screen("Discover", systemImage: "sparkles", note: "Explore, Charts, Moods, New releases arrive in K7.")
            }
            SwiftUI.Tab("Collections", systemImage: "square.stack", value: Tab.collections) {
                self.screen("Collections", systemImage: "square.stack", note: "Library, Liked music, History arrive in K8.")
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayerView(
                namespace: self.nowPlayingNamespace,
                onTap: { self.isNowPlayingPresented = true }
            )
        }
        .fullScreenCover(isPresented: self.$isNowPlayingPresented) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "miniPlayer", in: self.nowPlayingNamespace))
        }
    }

    /// Placeholder tab content with its own navigation stack and the settings entry point.
    private func screen(_ title: String, systemImage: String, note: String) -> some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView(title, systemImage: systemImage, description: Text(note))
                    .padding(.top, 80)
            }
            .navigationTitle(title)
            .toolbar { SettingsToolbarButton() }
        }
    }
}
