import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context _: Context) -> WKWebView { self.webView }
    func updateUIView(_: WKWebView, context _: Context) {}
}

struct ContentView: View {
    @StateObject private var model = PlayerModel()
    @ObservedObject private var log = SpikeLog.shared

    @AppStorage("desktopUA") private var desktopUA = true
    @AppStorage("spoofVisibility") private var spoofVisibility = false
    @AppStorage("autoConfirm") private var autoConfirm = true
    @AppStorage("resumeOnBackground") private var resumeOnBackground = false
    @AppStorage("hideWebView") private var hideWebView = false
    @AppStorage("keepAlive") private var keepAlive = false
    @AppStorage("nativeTransport") private var nativeTransport = false

    @State private var urlText = ""
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            WebViewHost(webView: self.model.webView)
                .id(self.model.generation)
                .frame(
                    maxWidth: self.hideWebView ? 1 : .infinity,
                    maxHeight: self.hideWebView ? 1 : .infinity
                )
                .opacity(self.hideWebView ? 0 : 1)

            Divider()
            self.panel
                .frame(maxHeight: self.hideWebView ? .infinity : 280)
        }
        .sheet(isPresented: self.$showSettings) { self.settingsSheet }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                self.commandButton("backward.fill", "prev")
                self.commandButton("playpause.fill", "toggle")
                self.commandButton("forward.fill", "next")
                self.commandButton("play.fill", "play")
                self.commandButton("pause.fill", "pause")
                Spacer()
                Button("Réglages") { self.showSettings = true }
                    .font(.footnote)
            }
            .padding(.horizontal)
            .padding(.top, 6)

            self.nowPlaying
                .padding(.horizontal)

            self.reportCard
                .padding(.horizontal)

            HStack {
                Text("Log (\(self.log.fileURL.lastPathComponent))").font(.caption.bold())
                Spacer()
                ShareLink(item: self.log.fileURL) { Image(systemName: "square.and.arrow.up") }
                Button("Vider") { self.log.clear() }.font(.caption)
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(self.log.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: self.log.lines.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func commandButton(_ systemImage: String, _ command: String) -> some View {
        Button {
            Task { await self.model.run(command) }
        } label: {
            Image(systemName: systemImage).frame(minWidth: 28, minHeight: 28)
        }
    }

    private var nowPlaying: some View {
        let s = self.model.snapshot
        let state = s?.paused.map { $0 ? "⏸ paused" : "▶︎ playing" } ?? "no media"
        let time = s?.currentTime.map { String(format: "%.0f", $0) } ?? "-"
        let total = s?.duration.map { String(format: "%.0f", $0) } ?? "-"
        return Text("\(state) \(time)/\(total)s · vis=\(s?.visibility ?? "?") · \(s?.title ?? "—")")
            .font(.caption)
            .lineLimit(1)
    }

    @ViewBuilder
    private var reportCard: some View {
        if let report = self.model.activeReport {
            Text("⏺ En arrière-plan depuis \(Int(report.duration))s — hb JS \(report.jsHeartbeats), ticks natifs \(report.nativeTicks)")
                .font(.caption2)
        } else if let report = self.model.lastReport {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dernier test arrière-plan : \(Int(report.duration))s")
                    .font(.caption.bold())
                Text(
                    "lecture \(Self.flag(report.playingAtStart)) → \(Self.flag(report.playingAtEnd)) · pistes changées \(report.trackChanges) · pauses \(report.pauseEvents) · "
                        + "hb JS \(report.jsHeartbeats) (trou max \(Int(report.maxJSGap))s) · ticks natifs \(report.nativeTicks) (trou max \(Int(report.maxNativeGap))s) · "
                        + "reprises \(report.resumeAttempts)\(report.webContentTerminated ? " · ⚠︎ WebContent tué" : "")"
                )
                .font(.caption2)
            }
        } else {
            Text("Mets l'app en arrière-plan (ou verrouille) pendant la lecture, puis reviens : un rapport s'affiche ici.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private static func flag(_ value: Bool?) -> String {
        value.map { $0 ? "▶︎" : "⏸" } ?? "?"
    }

    // MARK: - Settings

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Appliqué après « Recharger »") {
                    Toggle("User-Agent desktop (Safari macOS)", isOn: self.$desktopUA)
                    Toggle("Mentir sur la visibilité de la page", isOn: self.$spoofVisibility)
                    Toggle("Auto-confirmer « Continuer ? »", isOn: self.$autoConfirm)
                    Toggle("Keep-alive : audio Web silencieux (pause)", isOn: self.$keepAlive)
                    Button("Recharger music.youtube.com") {
                        self.model.reload()
                        self.showSettings = false
                    }
                }
                Section("Immédiat") {
                    Toggle("Relancer play() en passant en arrière-plan", isOn: self.$resumeOnBackground)
                    Toggle("Play/pause écran verrouillé natifs", isOn: self.$nativeTransport)
                    Toggle("Cacher la WebView (1×1, comme Kaset)", isOn: self.$hideWebView)
                }
                Section("Ouvrir une URL") {
                    TextField("https://music.youtube.com/playlist?list=…", text: self.$urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Aller") {
                        self.model.open(self.urlText)
                        self.showSettings = false
                    }
                }
            }
            .navigationTitle("Réglages du spike")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { self.showSettings = false }
                }
            }
        }
    }
}
