import SwiftUI

@main
struct KasetApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(self.environment)
                .tint(Color.brand)
        }
    }
}

extension Color {
    /// The red-pink of the app icon (kaset's cassette), used as the accent colour.
    static let brand = Color(red: 252 / 255, green: 19 / 255, blue: 85 / 255)
}
