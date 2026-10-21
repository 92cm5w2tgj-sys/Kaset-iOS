import SwiftUI

/// Which parts of the YouTube Music page the app drives still respond. Refreshes while open,
/// so a DOM change after a YouTube Music update is visible at a glance.
struct PlayerHealthView: View {
    let player: WebPlayer

    var body: some View {
        List {
            if let report = self.player.healthReport {
                Section {
                    self.summary(report)
                }
                Section {
                    ForEach(report.checks) { check in
                        self.row(check)
                    }
                } footer: {
                    Text("Checked \(report.date.formatted(date: .omitted, time: .standard)). "
                        + "Nothing is clicked: the probe only looks the elements up.")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Player health")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Check now", systemImage: "arrow.clockwise") {
                    Task { await self.player.checkHealth() }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await self.player.checkHealth()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func summary(_ report: PlayerHealthReport) -> some View {
        let failing = report.failing.count
        let waiting = report.checks.filter { $0.status == .needsTrack }.count
        return VStack(alignment: .leading, spacing: 4) {
            Label(
                failing == 0 ? "Everything responds" : "\(failing) failing",
                systemImage: failing == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(failing == 0 ? .green : .red)
            if waiting > 0 {
                Text("\(waiting) checks need a track playing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ check: PlayerHealthReport.Check) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: Self.symbol(check.status))
                .foregroundStyle(Self.color(check.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                if !check.usedBy.isEmpty {
                    Text(check.usedBy).font(.caption).foregroundStyle(.secondary)
                }
                if !check.detail.isEmpty {
                    Text(check.detail).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func symbol(_ status: PlayerHealthReport.Status) -> String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .failing: "xmark.octagon.fill"
        case .needsTrack: "circle.dashed"
        }
    }

    private static func color(_ status: PlayerHealthReport.Status) -> Color {
        switch status {
        case .ok: .green
        case .failing: .red
        case .needsTrack: .secondary
        }
    }
}
