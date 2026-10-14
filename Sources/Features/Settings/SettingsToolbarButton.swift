import SwiftUI

/// Account button shown in every tab's navigation bar; presents the settings sheet.
struct SettingsToolbarButton: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SettingsSheetButton()
        }
    }
}

private struct SettingsSheetButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Settings", systemImage: "person.crop.circle") { self.isPresented = true }
            .sheet(isPresented: self.$isPresented) { SettingsView() }
    }
}
