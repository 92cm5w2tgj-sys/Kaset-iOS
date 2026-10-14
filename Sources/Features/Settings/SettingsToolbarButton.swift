import SwiftUI

/// Account button shown in every tab's navigation bar; presents the settings sheet.
/// Shows the user's avatar when signed in, a person glyph otherwise.
struct SettingsToolbarButton: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SettingsSheetButton()
        }
    }
}

private struct SettingsSheetButton: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isPresented = false

    var body: some View {
        Button { self.isPresented = true } label: {
            if let url = self.environment.accountAvatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: self.$isPresented) { SettingsView() }
    }
}
