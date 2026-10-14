import AVKit
import Observation
import SwiftUI

/// Rating and lyrics for the track the page is playing. The track itself comes from
/// `PlaybackState`; this only adds what the web player does not report.
@MainActor
@Observable
final class NowPlayingModel {
    private(set) var likeStatus: LikeStatus = .indifferent
    private(set) var lyrics: Lyrics?
    private(set) var isLoadingLyrics = false
    private var loadedVideoId: String?
    private let client: YTMusicClient

    init(client: YTMusicClient) {
        self.client = client
    }

    func trackChanged(to videoId: String?) async {
        guard videoId != self.loadedVideoId else { return }
        self.loadedVideoId = videoId
        self.lyrics = nil
        self.likeStatus = .indifferent
        guard let videoId else { return }
        if let song = try? await self.client.getSong(videoId: videoId), self.loadedVideoId == videoId {
            self.likeStatus = song.likeStatus ?? .indifferent
        }
    }

    func toggleLike(videoId: String) async {
        let next: LikeStatus = self.likeStatus == .like ? .indifferent : .like
        let previous = self.likeStatus
        self.likeStatus = next
        do {
            try await self.client.rateSong(videoId: videoId, rating: next)
        } catch {
            self.likeStatus = previous
        }
    }

    func loadLyrics(videoId: String) async {
        guard self.lyrics == nil else { return }
        self.isLoadingLyrics = true
        defer { self.isLoadingLyrics = false }
        self.lyrics = (try? await self.client.getLyrics(videoId: videoId)) ?? .unavailable
    }
}

/// Full-screen player. Every control sends a command to the web player; what is drawn comes
/// from `PlaybackState`, which only changes when the page reports back.
struct NowPlayingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model: NowPlayingModel?
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isQueuePresented = false
    @State private var isLyricsPresented = false

    var body: some View {
        let state = self.environment.player.state

        VStack(spacing: 20) {
            Capsule().fill(.secondary).frame(width: 36, height: 5).padding(.top, 8)
            ArtworkView(url: state.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 12, y: 6)
                .scaleEffect(state.isPlaying ? 1 : 0.88)
                .animation(.spring(duration: 0.4), value: state.isPlaying)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            self.titleRow(state)
            self.scrubber(state)
            self.transport(state)
            Spacer(minLength: 0)
            self.footer(state)
        }
        .padding(.horizontal)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task(id: state.videoId) {
            let model = self.model ?? NowPlayingModel(client: self.environment.client)
            self.model = model
            await model.trackChanged(to: state.videoId)
        }
        .sheet(isPresented: self.$isQueuePresented) { QueueView() }
        .sheet(isPresented: self.$isLyricsPresented) {
            LyricsSheet(model: self.model, videoId: state.videoId)
        }
    }

    private func titleRow(_ state: PlaybackState) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title ?? "Not playing").font(.title3.bold()).lineLimit(1)
                Text(state.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let videoId = state.videoId, let model {
                Button {
                    Task { await model.toggleLike(videoId: videoId) }
                } label: {
                    Image(systemName: model.likeStatus == .like ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(model.likeStatus == .like ? Color.pink : Color.primary)
                }
                .accessibilityLabel(model.likeStatus == .like ? "Unlike" : "Like")
            }
        }
    }

    private func scrubber(_ state: PlaybackState) -> some View {
        VStack(spacing: 2) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = self.isScrubbing ? self.scrubValue : state.position(at: context.date)
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(get: { position }, set: { self.scrubValue = $0 }),
                        in: 0 ... max(state.duration, 1)
                    ) { editing in
                        self.isScrubbing = editing
                        if !editing { self.environment.player.seek(to: self.scrubValue) }
                    }
                    .disabled(state.duration <= 0)
                    HStack {
                        Text(Self.format(position))
                        Spacer()
                        Text("-" + Self.format(max(0, state.duration - position)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transport(_ state: PlaybackState) -> some View {
        HStack(spacing: 36) {
            Button { self.environment.player.toggleShuffle() } label: {
                Image(systemName: "shuffle").foregroundStyle(state.isShuffleEnabled ? Color.accentColor : Color.secondary)
            }
            .accessibilityLabel("Shuffle")
            Button { Haptics.tap(); self.environment.player.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            .disabled(!state.canGoPrevious)
            .accessibilityLabel("Previous")
            Button { Haptics.tap(); self.environment.player.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 68))
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Button { Haptics.tap(); self.environment.player.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .disabled(!state.canGoNext)
            .accessibilityLabel("Next")
            Button { self.environment.player.cycleRepeat() } label: {
                Image(systemName: state.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(state.repeatMode == .off ? Color.secondary : Color.accentColor)
            }
            .accessibilityLabel("Repeat")
        }
        .font(.title3)
    }

    private func footer(_ state: PlaybackState) -> some View {
        HStack {
            Button { self.isLyricsPresented = true } label: { Image(systemName: "quote.bubble") }
                .accessibilityLabel("Lyrics")
            Spacer()
            AirPlayButton().frame(width: 36, height: 36)
            Spacer()
            Button { self.isQueuePresented = true } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("Queue")
        }
        .font(.title2)
        .padding(.horizontal, 24)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .tintColor
        view.tintColor = .label
        return view
    }

    func updateUIView(_: AVRoutePickerView, context _: Context) {}
}

struct LyricsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: NowPlayingModel?
    let videoId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model, model.isLoadingLyrics {
                    ProgressView().padding(.top, 40)
                } else if let lyrics = model?.lyrics, lyrics.isAvailable {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lyrics.text).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                        if let source = lyrics.source {
                            Text(source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView("No lyrics", systemImage: "quote.bubble")
                        .padding(.top, 40)
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.dismiss() } } }
        }
        .task {
            if let videoId { await self.model?.loadLyrics(videoId: videoId) }
        }
    }
}
