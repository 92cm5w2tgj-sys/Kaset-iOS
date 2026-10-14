import SwiftUI

@main
struct KasetApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(self.environment)
        }
    }
}
