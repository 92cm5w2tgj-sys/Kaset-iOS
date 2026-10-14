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
    @State private var isQueuePresented = false
    @State private var isLyricsPresented = false

    var body: some View {
        let state = self.environment.player.state

        ZStack {
            self.background(state)

            VStack(spacing: 0) {
                self.topBar
                Spacer(minLength: 12)
                ArtworkView(url: state.artworkURL)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
                    .scaleEffect(state.isPlaying ? 1 : 0.9)
                    .animation(.spring(duration: 0.45, bounce: 0.25), value: state.isPlaying)
                    .padding(.horizontal, 12)
                Spacer(minLength: 24)

                VStack(spacing: 22) {
                    self.titleRow(state)
                    ScrubberView(state: state) { self.environment.player.seek(to: $0) }
                    self.transport(state)
                }
                Spacer(minLength: 20)
                self.footer(state)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
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

    /// Blurred, darkened artwork behind the controls (Apple Music style).
    private func background(_ state: PlaybackState) -> some View {
        ZStack {
            Color.black
            ArtworkView(url: state.artworkURL)
                .scaledToFill()
                .scaleEffect(1.6)
                .blur(radius: 70)
                .saturation(1.25)
                .opacity(0.75)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: state.artworkURL)
    }

    private var topBar: some View {
        HStack {
            Button { self.dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.top, 4)
    }

    private func titleRow(_ state: PlaybackState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title ?? "Not playing")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text(state.artist ?? " ")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let videoId = state.videoId, let model {
                Button {
                    Haptics.tap()
                    Task { await model.toggleLike(videoId: videoId) }
                } label: {
                    Image(systemName: model.likeStatus == .like ? "heart.fill" : "heart")
                        .font(.title3)
                        .symbolEffect(.bounce, value: model.likeStatus)
                        .foregroundStyle(model.likeStatus == .like ? Color.pink : Color.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.likeStatus == .like ? "Unlike" : "Like")
            }
        }
    }

    private func transport(_ state: PlaybackState) -> some View {
        HStack {
            Spacer()
            Button { Haptics.tap(); self.environment.player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 34))
            }
            .disabled(!state.canGoPrevious)
            .accessibilityLabel("Previous")
            Spacer()
            Button { Haptics.tap(); self.environment.player.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { Haptics.tap(); self.environment.player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 34))
            }
            .disabled(!state.canGoNext)
            .accessibilityLabel("Next")
            Spacer()
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.white)
    }

    private func footer(_ state: PlaybackState) -> some View {
        HStack {
            self.footerButton("shuffle", isOn: state.isShuffleEnabled, label: "Shuffle") {
                self.environment.player.toggleShuffle()
            }
            self.footerButton(state.repeatMode == .one ? "repeat.1" : "repeat", isOn: state.repeatMode != .off, label: "Repeat") {
                self.environment.player.cycleRepeat()
            }
            self.footerButton("quote.bubble", isOn: false, label: "Lyrics") { self.isLyricsPresented = true }
            AirPlayButton()
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
            self.footerButton("list.bullet", isOn: false, label: "Queue") { self.isQueuePresented = true }
        }
    }

    private func footerButton(_ symbol: String, isOn: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background { if isOn { Circle().fill(.white.opacity(0.9)) } }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Progress bar with a drag-to-seek gesture. While dragging it shows the finger position;
/// on release it sends one `seek` command and keeps showing that position until the page
/// reports a time near it (or a short timeout), so it does not jump back.
struct ScrubberView: View {
    let state: PlaybackState
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var pendingSeek: (target: TimeInterval, until: Date)?

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let duration = max(self.state.duration, 0)
                let position = self.displayedPosition(at: context.date, duration: duration)
                let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0

                VStack(spacing: 6) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.28))
                            Capsule().fill(.white).frame(width: max(proxy.size.width * fraction, 0))
                        }
                        .frame(height: self.dragFraction == nil ? 6 : 12)
                        .clipShape(Capsule())
                        .animation(.spring(duration: 0.25), value: self.dragFraction == nil)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard duration > 0 else { return }
                                    self.dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                                }
                                .onEnded { value in
                                    guard duration > 0 else { return }
                                    let target = min(max(value.location.x / proxy.size.width, 0), 1) * duration
                                    self.dragFraction = nil
                                    self.pendingSeek = (target, Date().addingTimeInterval(3))
                                    self.onSeek(target)
                                }
                        )
                    }
                    .frame(height: 28)

                    HStack {
                        Text(Self.format(position))
                        Spacer()
                        Text("-" + Self.format(max(0, duration - position)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .opacity(self.state.duration > 0 ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.format(self.state.position())) of \(Self.format(self.state.duration))")
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 10
            let current = self.state.position()
            switch direction {
            case .increment: self.onSeek(min(current + step, self.state.duration))
            case .decrement: self.onSeek(max(current - step, 0))
            @unknown default: break
            }
        }
    }

    private func displayedPosition(at date: Date, duration: TimeInterval) -> TimeInterval {
        if let dragFraction { return dragFraction * duration }
        let live = self.state.position(at: date)
        if let pending = self.pendingSeek {
            // Hold the target until the page catches up with it (within 2 s) or the timeout.
            if date < pending.until, abs(live - pending.target) > 2 { return pending.target }
        }
        return live
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Subtle scale-down on press, used for the player's icon buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context _: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .white
        view.tintColor = UIColor.white.withAlphaComponent(0.85)
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
