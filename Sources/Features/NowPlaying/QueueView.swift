import SwiftUI

/// The page's queue, as last reported. Jump / remove are commands to the page; the list
/// updates when the page reports a new queue.
struct QueueView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let queue = self.environment.player.state.queue

        NavigationStack {
            Group {
                if queue.isEmpty {
                    ContentUnavailableView("Queue is empty", systemImage: "list.bullet",
                                           description: Text("Play something to see what's next."))
                } else {
                    List(queue) { entry in
                        Button {
                            self.environment.player.playQueueEntry(at: entry.index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.isCurrent ? "speaker.wave.2.fill" : "music.note")
                                    .frame(width: 24)
                                    .foregroundStyle(entry.isCurrent ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title.isEmpty ? entry.videoId : entry.title).lineLimit(1)
                                    if !entry.artist.isEmpty {
                                        Text(entry.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !entry.isCurrent {
                                Button("Remove", role: .destructive) {
                                    self.environment.player.removeQueueEntry(at: entry.index)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    let state = self.environment.player.state
                    Button { self.environment.player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .symbolVariant(state.isShuffleEnabled ? .fill : .none)
                            .foregroundStyle(state.isShuffleEnabled ? Color.accentColor : Color.secondary)
                    }
                    .accessibilityLabel("Shuffle")
                    Button { self.environment.player.cycleRepeat() } label: {
                        Image(systemName: state.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(state.repeatMode == .off ? Color.secondary : Color.accentColor)
                    }
                    .accessibilityLabel("Repeat")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { self.dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
