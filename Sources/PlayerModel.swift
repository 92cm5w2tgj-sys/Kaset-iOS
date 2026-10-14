import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit
import WebKit

struct PlayerSnapshot {
    var paused: Bool?
    var title: String?
    var currentTime: Double?
    var duration: Double?
    var visibility: String?
    var receivedAt = Date()
}

/// Facts collected between "app entered background" and "app is about to enter foreground".
struct BackgroundReport {
    var startedAt = Date()
    var endedAt: Date?
    var playingAtStart: Bool?
    var playingAtEnd: Bool?
    var jsHeartbeats = 0
    var maxJSGap: TimeInterval = 0
    var nativeTicks = 0
    var maxNativeGap: TimeInterval = 0
    var pauseEvents = 0
    var endedEvents = 0
    var errorEvents = 0
    var trackChanges = 0
    var resumeAttempts = 0
    var audioInterruptions = 0
    var webContentTerminated = false

    var duration: TimeInterval { (self.endedAt ?? Date()).timeIntervalSince(self.startedAt) }
}

@MainActor
private final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: PlayerModel?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        self.target?.handle(body)
    }
}

@MainActor
final class PlayerModel: NSObject, ObservableObject {
    static let homeURL = URL(string: "https://music.youtube.com")!
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    @Published private(set) var webView: WKWebView
    @Published private(set) var generation = 0
    @Published private(set) var snapshot: PlayerSnapshot?
    @Published private(set) var activeReport: BackgroundReport?
    @Published private(set) var lastReport: BackgroundReport?
    @Published private(set) var lastCommandResult = ""

    private let log = SpikeLog.shared
    private let proxy: ScriptProxy
    private var lastHeartbeat: Date?
    private var lastNativeTick = Date()
    private var lastTitle: String?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    override init() {
        let proxy = ScriptProxy()
        self.proxy = proxy
        self.webView = Self.buildWebView(proxy: proxy)
        super.init()
        proxy.target = self
        self.attach(self.webView)
        self.configureAudioSession()
        self.configureTransportCommands()
        self.observeAudioSession()
        self.observeLifecycle()
        self.startNativeTicker()
        self.webView.load(URLRequest(url: Self.homeURL))
        self.log.log("boot", "desktopUA=\(SpikeSettings.desktopUserAgent) spoofVisibility=\(SpikeSettings.spoofVisibility) "
            + "autoConfirm=\(SpikeSettings.autoConfirm) resumeOnBackground=\(SpikeSettings.resumeOnBackground)")
    }

    // MARK: - Web view

    private static func buildWebView(proxy: ScriptProxy) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false

        // Makes the default UA read exactly like Mobile Safari; Google refuses sign-in
        // ("Something went wrong") from web views that don't look like Safari.
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let preferences = WKWebpagePreferences()
        preferences.preferredContentMode = SpikeSettings.desktopUserAgent ? .desktop : .mobile
        configuration.defaultWebpagePreferences = preferences

        let script = WKUserScript(
            source: PageScript.source(
                spoofVisibility: SpikeSettings.spoofVisibility,
                autoConfirm: SpikeSettings.autoConfirm,
                keepAlive: SpikeSettings.keepAlive
            ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(proxy, name: "spike")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if SpikeSettings.desktopUserAgent {
            webView.customUserAgent = Self.desktopUserAgent
        }
        webView.isInspectable = true // Safari ▸ Develop ▸ <device> to look at the page live.
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    private func attach(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Rebuilds the web view so changed settings (UA, injected script) take effect.
    func reload() {
        let old = self.webView
        old.stopLoading()
        old.configuration.userContentController.removeScriptMessageHandler(forName: "spike")
        old.load(URLRequest(url: URL(string: "about:blank")!))

        let fresh = Self.buildWebView(proxy: self.proxy)
        self.attach(fresh)
        self.webView = fresh
        self.generation += 1
        self.snapshot = nil
        self.lastTitle = nil
        self.lastHeartbeat = nil
        fresh.load(URLRequest(url: Self.homeURL))
        self.log.log("web", "reloaded: desktopUA=\(SpikeSettings.desktopUserAgent) spoofVisibility=\(SpikeSettings.spoofVisibility) "
            + "autoConfirm=\(SpikeSettings.autoConfirm)")
    }

    func open(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            self.log.log("web", "ignored invalid URL: \(trimmed)")
            return
        }
        self.webView.load(URLRequest(url: url))
    }

    // MARK: - Commands

    @discardableResult
    func run(_ command: String) async -> String {
        let js = "window.__spike ? String(window.__spike.\(command)()) : 'no-spike'"
        let result: String
        do {
            result = (try await self.webView.evaluateJavaScript(js) as? String) ?? "nil"
        } catch {
            result = "error: \(error.localizedDescription)"
        }
        self.lastCommandResult = "\(command) → \(result)"
        self.log.log("cmd", "\(command) → \(result)")
        return result
    }

    func refreshSnapshot() async {
        let js = "JSON.stringify(window.__spike ? window.__spike.snapshot() : null)"
        guard let text = try? await self.webView.evaluateJavaScript(js) as? String,
              let data = text.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        self.ingest(dict)
    }

    // MARK: - Bridge messages

    func handle(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String else { return }
        switch kind {
        case "hb":
            let now = Date()
            if let previous = self.lastHeartbeat {
                let gap = now.timeIntervalSince(previous)
                if gap > 12 {
                    self.log.log("js", "GAP \(Int(gap))s between heartbeats (page timers throttled or process suspended)")
                }
                self.activeReport?.maxJSGap = max(self.activeReport?.maxJSGap ?? 0, gap)
            }
            self.lastHeartbeat = now
            self.activeReport?.jsHeartbeats += 1
            self.ingest(message)
            self.log.log("hb", self.summary(message))
        case "media":
            let event = message["ev"] as? String ?? "?"
            self.ingest(message)
            self.log.log("media", "\(event) \(self.summary(message))")
            if self.activeReport != nil {
                switch event {
                case "pause": self.activeReport?.pauseEvents += 1
                case "ended": self.activeReport?.endedEvents += 1
                case "error", "stalled": self.activeReport?.errorEvents += 1
                default: break
                }
            }
        case "vis":
            self.ingest(message)
            self.log.log("vis", "visibilitychange real=\(message["vis"] as? String ?? "?") spoofed=\(message["spoofed"] as? Bool ?? false)")
        case "boot":
            self.log.log("js", "page script booted \(message["path"] as? String ?? "") vis=\(message["vis"] as? String ?? "?")")
        case "ka":
            self.log.log("keepalive", "AudioContext \(message["state"] as? String ?? "?")")
        case "ms":
            self.log.log("remote", "mediaSession \(message["action"] as? String ?? "?") \(message["msg"] as? String ?? "")")
        case "dialog":
            self.log.log("js", "dialog \(message["tag"] as? String ?? "?") clicked=\(message["clicked"] as? Bool ?? false)")
        case "playerr":
            self.log.log("js", "play() rejected: \(message["msg"] as? String ?? "?")")
        default:
            self.log.log("js", "unknown message \(kind)")
        }
    }

    private func ingest(_ dict: [String: Any]) {
        var next = PlayerSnapshot()
        next.paused = dict["paused"] as? Bool
        next.title = dict["title"] as? String
        next.currentTime = dict["currentTime"] as? Double
        next.duration = dict["duration"] as? Double
        next.visibility = dict["vis"] as? String
        self.snapshot = next

        if let title = next.title, !title.isEmpty {
            if let previous = self.lastTitle, previous != title {
                self.log.log("track", "CHANGE '\(previous)' → '\(title)' (background=\(self.activeReport != nil))")
                self.activeReport?.trackChanges += 1
            }
            self.lastTitle = title
        }
    }

    private func summary(_ d: [String: Any]) -> String {
        let paused = (d["paused"] as? Bool).map { $0 ? "paused" : "playing" } ?? "no-media"
        let time = (d["currentTime"] as? Double).map { String(format: "%.0f", $0) } ?? "-"
        let duration = (d["duration"] as? Double).map { String(format: "%.0f", $0) } ?? "-"
        let vis = d["vis"] as? String ?? "?"
        let title = (d["title"] as? String) ?? ""
        return "\(paused) \(time)/\(duration)s vis=\(vis) '\(title.prefix(32))'"
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        let names: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "willResignActive"),
            (UIApplication.didEnterBackgroundNotification, "didEnterBackground"),
            (UIApplication.willEnterForegroundNotification, "willEnterForeground"),
            (UIApplication.didBecomeActiveNotification, "didBecomeActive"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "deviceLocking"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "deviceUnlocked"),
            (UIApplication.didReceiveMemoryWarningNotification, "memoryWarning"),
        ]
        for (name, label) in names {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.lifecycle(label)
                }
            }
        }
    }

    private func lifecycle(_ label: String) {
        self.log.log("app", label)
        switch label {
        case "didEnterBackground":
            self.beginReport()
        case "willEnterForeground":
            self.finishReport()
        default:
            break
        }
    }

    private func beginReport() {
        var report = BackgroundReport()
        report.playingAtStart = self.snapshot?.paused.map { !$0 }
        self.activeReport = report
        self.lastNativeTick = Date()
        guard SpikeSettings.resumeOnBackground, report.playingAtStart == true else { return }
        self.resumeBurst()
    }

    private func finishReport() {
        Task {
            await self.refreshSnapshot()
            guard var report = self.activeReport else { return }
            report.endedAt = Date()
            report.playingAtEnd = self.snapshot?.paused.map { !$0 }
            self.activeReport = nil
            self.lastReport = report
            self.log.log("report", "bg=\(Int(report.duration))s playing \(String(describing: report.playingAtStart)) → "
                + "\(String(describing: report.playingAtEnd)) hb=\(report.jsHeartbeats) maxJSGap=\(Int(report.maxJSGap))s "
                + "nativeTicks=\(report.nativeTicks) maxNativeGap=\(Int(report.maxNativeGap))s pauses=\(report.pauseEvents) "
                + "ended=\(report.endedEvents) tracks=\(report.trackChanges) resumes=\(report.resumeAttempts)")
        }
    }

    /// Known workaround: when the app goes to background YouTube may pause the media element.
    /// Re-issue `play()` a few times while we still hold a background task.
    private func resumeBurst() {
        self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "spike-resume") { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
        Task {
            for delay in [0.3, 0.8, 1.5, 3.0] as [Double] {
                try? await Task.sleep(for: .seconds(delay))
                await self.refreshSnapshot()
                if self.snapshot?.paused == true {
                    self.activeReport?.resumeAttempts += 1
                    await self.run("play")
                }
            }
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    /// Distinguishes "WebContent process throttled" from "whole app suspended".
    private func startNativeTicker() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let now = Date()
                if self.activeReport != nil {
                    let gap = now.timeIntervalSince(self.lastNativeTick)
                    self.activeReport?.nativeTicks += 1
                    self.activeReport?.maxNativeGap = max(self.activeReport?.maxNativeGap ?? 0, gap)
                    if gap > 12 {
                        self.log.log("native", "GAP \(Int(gap))s (app was suspended)")
                    }
                }
                self.lastNativeTick = now
                self.assertTransportCommands()
            }
        }
    }

    // MARK: - Lock screen commands

    private var lastRemoteCommand = Date.distantPast

    /// WebKit exposes ±10 s skips because the page registers no next/previous handlers.
    /// Register real next/previous commands that click YouTube Music's own buttons.
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.addTarget { [weak self] _ in self?.remote("next") ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.remote("prev") ?? .commandFailed }
        self.assertRemoteCommandState()
    }

    private func remote(_ command: String) -> MPRemoteCommandHandlerStatus {
        // Guard against WebKit also forwarding the same press.
        guard Date().timeIntervalSince(self.lastRemoteCommand) > 0.6 else { return .success }
        self.lastRemoteCommand = Date()
        self.log.log("remote", "lock screen \(command)")
        Task { await self.run(command) }
        return .success
    }

    /// WebKit may re-enable the skip commands whenever the media session updates.
    private func assertRemoteCommandState() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Native play/pause (experiment)

    /// The log showed the app process alive (native ticker never stalled) while the WebContent
    /// process froze after a pause. Lock-screen play then goes to a frozen page. Handle play/pause
    /// natively and drive the page with evaluateJavaScript, which has to wake the process.
    private func configureTransportCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.transport("play") ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.transport("pause") ?? .commandFailed }
    }

    private func transport(_ command: String) -> MPRemoteCommandHandlerStatus {
        guard SpikeSettings.nativeTransport else { return .commandFailed }
        let started = Date()
        self.log.log("remote", "native \(command) requested (last JS heartbeat \(self.lastHeartbeat.map { Int(Date().timeIntervalSince($0)) } ?? -1)s ago)")
        try? AVAudioSession.sharedInstance().setActive(true)
        Task {
            let result = await self.run(command)
            self.log.log("remote", "native \(command) done in \(Int(Date().timeIntervalSince(started) * 1000)) ms → \(result)")
        }
        return .success
    }

    private func assertTransportCommands() {
        guard SpikeSettings.nativeTransport else { return }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            self.log.log("audio", "session active category=\(session.category.rawValue) outputs=\(self.outputs())")
        } catch {
            self.log.log("audio", "session setup FAILED: \(error.localizedDescription)")
        }
    }

    private func outputs() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
    }

    private func observeAudioSession() {
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                self?.audioInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                self?.log.log("audio", "routeChange reason=\(reason) outputs=\(self?.outputs() ?? "?")")
            }
        }
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                self?.log.log("audio", "MEDIA SERVICES RESET")
            }
        }
    }

    private func audioInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            self.activeReport?.audioInterruptions += 1
            self.log.log("audio", "interruption BEGAN")
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            self.log.log("audio", "interruption ENDED shouldResume=\(options.contains(.shouldResume))")
            try? AVAudioSession.sharedInstance().setActive(true)
            if options.contains(.shouldResume) {
                Task { await self.run("play") }
            }
        @unknown default:
            break
        }
    }
}

extension PlayerModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        self.log.log("nav", "didFinish \(self.webView.url?.absoluteString.prefix(80) ?? "")")
    }

    func webView(_: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.log.log("nav", "didFail \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.log.log("nav", "didFailProvisional \(error.localizedDescription)")
    }

    /// The single most important signal: iOS killed the page's process while we were in the background.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.log.log("nav", "WEBCONTENT PROCESS TERMINATED")
        self.activeReport?.webContentTerminated = true
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        // Sign-in flows open popups; keep them in the same view.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
