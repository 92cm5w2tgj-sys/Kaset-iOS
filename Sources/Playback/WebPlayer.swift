import AVFoundation
import MediaPlayer
import Observation
import UIKit
import WebKit

@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebPlayer?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        self.target?.handle(body)
    }
}

/// The playback engine: a hidden `music.youtube.com` web view that owns the queue.
///
/// Commands are forwarded to the page; `state` only changes when the page reports back.
/// Evolved from the spike's `PlayerModel` (evidence in `docs/spike-findings.md`).
@MainActor
@Observable
final class WebPlayer: NSObject {
    static let homeURL = URL(string: "https://music.youtube.com")!
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private(set) var webView: WKWebView
    private(set) var state = PlaybackState()
    /// Result of the last play-next attempt: `(videoId, success, reason)`.
    private(set) var lastQueueResult: (videoId: String, success: Bool, reason: String)?
    private(set) var generation = 0
    /// When the page last reported anything, and the page's address; for the debug readout.
    private(set) var lastMessageAt: Date?
    private(set) var pageURL: String?

    @ObservationIgnored private let log = SpikeLog.shared
    @ObservationIgnored private let proxy = MessageProxy()
    @ObservationIgnored private let nowPlaying = NowPlayingPublisher()
    @ObservationIgnored private var lastBeat: Date?
    @ObservationIgnored private var lastRemoteCommand = Date.distantPast
    @ObservationIgnored private var queueAttempt = 0

    override init() {
        self.webView = Self.makeWebView(proxy: self.proxy)
        super.init()
        self.proxy.target = self
        self.attach(self.webView)
        self.configureAudioSession()
        self.observeAudioSession()
        self.observeLifecycle()
        self.configureRemoteCommands()
        self.webView.load(URLRequest(url: Self.homeURL))
    }

    // MARK: - Web view

    private static func makeWebView(proxy: MessageProxy) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Without inline playback iOS promotes the video to full screen; without these two
        // it also starts Picture in Picture (spike findings).
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let preferences = WKWebpagePreferences()
        preferences.preferredContentMode = .desktop
        configuration.defaultWebpagePreferences = preferences

        configuration.userContentController.addUserScript(WKUserScript(
            source: PlayerScripts.page, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        configuration.userContentController.add(proxy, name: PlayerScripts.bridgeName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.desktopUserAgent
        #if DEBUG
            webView.isInspectable = true
        #endif
        return webView
    }

    private func attach(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Rebuilds the web view (e.g. after sign-in so the page picks up the session).
    func reload() {
        let old = self.webView
        old.stopLoading()
        old.configuration.userContentController.removeScriptMessageHandler(forName: PlayerScripts.bridgeName)
        old.load(URLRequest(url: URL(string: "about:blank")!))

        let fresh = Self.makeWebView(proxy: self.proxy)
        self.attach(fresh)
        self.webView = fresh
        self.generation += 1
        self.state = PlaybackState()
        self.lastBeat = nil
        fresh.load(URLRequest(url: Self.homeURL))
        self.log.log("web", "reloaded")
    }

    // MARK: - Commands (forwarded to the page)

    /// Starts a song, optionally inside a playlist/radio so the page owns a real queue.
    func play(videoId: String?, playlistId: String? = nil) {
        guard videoId != nil || playlistId != nil else { return }
        var components = URLComponents(string: "https://music.youtube.com/watch")!
        var items: [URLQueryItem] = []
        if let videoId { items.append(URLQueryItem(name: "v", value: videoId)) }
        if let playlistId { items.append(URLQueryItem(name: "list", value: playlistId)) }
        components.queryItems = items
        guard let url = components.url else { return }
        self.log.log("cmd", "load watch v=\(videoId ?? "-") list=\(playlistId ?? "-")")
        self.webView.load(URLRequest(url: url))
    }

    func resume() { self.command("play") }
    func pause() { self.command("pause") }
    func togglePlayPause() { self.command("toggle") }
    func next() { self.command("next") }
    func previous() { self.command("previous") }

    func seek(to seconds: TimeInterval) {
        self.command("seek", argument: String(max(0, seconds)))
    }

    /// Asks the page to insert `videoId` right after the current track. The outcome comes back
    /// asynchronously in `lastQueueResult`; returns `false` if nothing is playing.
    @discardableResult
    func playNext(videoId: String) -> Bool {
        guard let source = self.state.videoId else {
            // Nothing is playing: "play next" is just "play".
            self.play(videoId: videoId, playlistId: "RDAMVM\(videoId)")
            return true
        }
        self.queueAttempt += 1
        let script = PlayerScripts.playNext(videoId: videoId, afterVideoId: source, attempt: self.queueAttempt)
        self.log.log("cmd", "playNext \(videoId) after \(source)")
        self.webView.evaluateJavaScript(script, completionHandler: nil)
        return true
    }

    /// Appends `videoId` to the end of the page's queue (outcome in `lastQueueResult`).
    @discardableResult
    func addToQueue(videoId: String) -> Bool {
        guard self.state.videoId != nil else {
            self.play(videoId: videoId, playlistId: "RDAMVM\(videoId)")
            return true
        }
        self.log.log("cmd", "addToQueue \(videoId)")
        self.webView.evaluateJavaScript(PlayerScripts.addToQueue(videoId: videoId), completionHandler: nil)
        return true
    }

    func refreshState() {
        Task {
            let js = "JSON.stringify(window.__kaset ? window.__kaset.state() : null)"
            guard let text = try? await self.webView.evaluateJavaScript(js) as? String,
                  let data = text.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            self.state = self.state.applying(message)
            self.publishNowPlaying()
        }
    }

    private func command(_ name: String, argument: String? = nil) {
        let call = "\(name)(\(argument ?? ""))"
        let js = "window.__kaset ? String(window.__kaset.\(call)) : 'no-page'"
        Task {
            let result: String
            do {
                result = (try await self.webView.evaluateJavaScript(js) as? String) ?? "nil"
            } catch {
                result = "error: \(error.localizedDescription)"
            }
            self.log.log("cmd", "\(call) → \(result)")
        }
    }

    // MARK: - Page messages

    fileprivate func handle(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String else { return }
        self.lastMessageAt = Date()
        switch kind {
        case "state":
            let now = Date()
            if message["hb"] as? Bool == true {
                if let previous = self.lastBeat, now.timeIntervalSince(previous) > 12 {
                    self.log.log("js", "GAP \(Int(now.timeIntervalSince(previous)))s between heartbeats")
                }
                self.lastBeat = now
            }
            let previousID = self.state.videoId
            self.state = self.state.applying(message, at: now)
            if self.state.videoId != previousID {
                self.log.log("track", "\(self.state.title ?? "?") — \(self.state.artist ?? "?") [\(self.state.videoId ?? "-")]")
            }
            if message["hb"] as? Bool != true {
                self.log.log("media", "\(message["ev"] as? String ?? "?") playing=\(self.state.isPlaying) "
                    + "\(Int(self.state.position))/\(Int(self.state.duration))s vis=\(self.state.visibility ?? "?")")
            }
            self.publishNowPlaying()
        case "queueResult":
            let id = message["videoId"] as? String ?? ""
            let success = message["success"] as? Bool ?? false
            let reason = message["reason"] as? String ?? ""
            self.lastQueueResult = (id, success, reason)
            self.log.log("queue", "playNext \(id) success=\(success) \(reason)")
        case "ka":
            self.log.log("keepalive", "AudioContext \(message["state"] as? String ?? "?")")
        case "ms":
            self.log.log("remote", "mediaSession \(message["action"] as? String ?? "?") \(message["msg"] as? String ?? "")")
        case "dialog":
            self.log.log("js", "dialog \(message["tag"] as? String ?? "?") clicked=\(message["clicked"] as? Bool ?? false)")
        case "playerr":
            self.log.log("js", "play() rejected: \(message["msg"] as? String ?? "?")")
        case "boot":
            self.log.log("js", "page script booted \(message["path"] as? String ?? "")")
        default:
            break
        }
    }

    // MARK: - Now Playing / remote commands

    var publishesNowPlaying: Bool {
        UserDefaults.standard.object(forKey: "nativeNowPlaying") as? Bool ?? true
    }

    private func publishNowPlaying() {
        guard self.publishesNowPlaying else {
            self.nowPlaying.clear()
            return
        }
        self.nowPlaying.update(from: self.state)
    }

    /// WebKit exposes ±10 s skips because the page registers no next/previous handlers.
    /// Register real commands that click the page's own buttons.
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.addTarget { [weak self] _ in self?.remote("next") ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.remote("previous") ?? .commandFailed }
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    private func remote(_ command: String) -> MPRemoteCommandHandlerStatus {
        // Guard against WebKit also forwarding the same press.
        guard Date().timeIntervalSince(self.lastRemoteCommand) > 0.6 else { return .success }
        self.lastRemoteCommand = Date()
        self.log.log("remote", "lock screen \(command)")
        self.command(command)
        return .success
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            self.log.log("audio", "session active outputs=\(self.outputs())")
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
                let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                self?.interruption(type: type, options: options)
            }
        }
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                self?.log.log("audio", "routeChange reason=\(reason) outputs=\(self?.outputs() ?? "?")")
            }
        }
    }

    private func interruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            self.log.log("audio", "interruption BEGAN")
        case .ended:
            let resume = AVAudioSession.InterruptionOptions(rawValue: options ?? 0).contains(.shouldResume)
            self.log.log("audio", "interruption ENDED shouldResume=\(resume)")
            try? AVAudioSession.sharedInstance().setActive(true)
            if resume { self.resume() }
        @unknown default:
            break
        }
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        let names: [(Notification.Name, String)] = [
            (UIApplication.didEnterBackgroundNotification, "didEnterBackground"),
            (UIApplication.willEnterForegroundNotification, "willEnterForeground"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "deviceLocking"),
            (UIApplication.didReceiveMemoryWarningNotification, "memoryWarning"),
        ]
        for (name, label) in names {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    self?.log.log("app", label)
                    if label == "willEnterForeground" { self?.refreshState() }
                }
            }
        }
    }
}

extension WebPlayer: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        self.pageURL = webView.url?.absoluteString
        self.log.log("nav", "didFinish \(webView.url?.absoluteString.prefix(80) ?? "")")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        self.log.log("nav", "didFail \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        self.log.log("nav", "didFailProvisional \(error.localizedDescription)")
    }

    /// iOS killed the page's process. Restoring track/position/queue is K11; for now reload.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.log.log("nav", "WEBCONTENT PROCESS TERMINATED")
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}
