import SwiftUI

/// Stub until K9: artwork, title, transport. Dismisses with the close button or a swipe.
struct NowPlayingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = self.environment.player.state

        VStack(spacing: 24) {
            Capsule().fill(.secondary).frame(width: 36, height: 5).padding(.top, 8)
            Spacer()
            ArtworkView(url: state.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)
            VStack(spacing: 4) {
                Text(state.title ?? "Not playing").font(.title3.bold())
                Text(state.artist ?? "").foregroundStyle(.secondary)
            }
            HStack(spacing: 40) {
                Button { self.environment.player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                .disabled(!state.canGoPrevious)
                Button { self.environment.player.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                }
                Button { self.environment.player.next() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                .disabled(!state.canGoNext)
            }
            Spacer()
            Button("Close") { self.dismiss() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
