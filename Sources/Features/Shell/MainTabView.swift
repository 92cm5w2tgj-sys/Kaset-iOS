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
                DiscoverView()
            }
            SwiftUI.Tab("Collections", systemImage: "square.stack", value: Tab.collections) {
                CollectionsView()
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                SearchView()
            }
        }
        .overlay(alignment: .top) {
            if let notice = self.environment.player.queueNotice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: self.environment.player.queueNotice)
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
}
