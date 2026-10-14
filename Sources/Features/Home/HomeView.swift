import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: BrowsePageModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    BrowsePageView(model: model, emptyMessage: "No recommendations yet.")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Home")
            .entityDestinations()
            .toolbar { SettingsToolbarButton() }
        }
        .task(id: self.environment.auth.state) {
            let model = self.model ?? BrowsePageModel(type: .home, client: self.environment.client)
            self.model = model
            await model.load(force: true)
        }
    }
}
