import JavaScriptCore
import Testing

@testable import KasetiOS

/// The page scripts are Swift string literals holding JavaScript: an escape such as `\n`
/// becomes a real newline inside a JS string and silently breaks the whole script on a device.
/// These tests run the scripts through JavaScriptCore (the same engine as the web view).
struct PageScriptTests {
    /// A tiny stand-in for the browser objects the page script touches at load time.
    private static let prelude = """
    var __posts = [];
    function setInterval() { return 0; }
    function setTimeout() { return 0; }
    function clearInterval() {}
    function clearTimeout() {}
    var document = {
      querySelector: function () { return null; },
      querySelectorAll: function () { return []; },
      getElementById: function () { return null; },
      addEventListener: function () {},
      body: { click: function () {} },
      hasFocus: function () { return true; }
    };
    function Document() {}
    Object.defineProperty(Document.prototype, 'visibilityState', { get: function () { return 'visible'; }, configurable: true });
    var HTMLElement = function () {};
    var MutationObserver = function () { this.observe = function () {}; this.disconnect = function () {}; };
    var navigator = { mediaSession: { setActionHandler: function () {}, metadata: null } };
    var location = { pathname: '/', search: '' };
    var window = {
      webkit: { messageHandlers: { kaset: { postMessage: function (o) { __posts.push(o); } } } },
      addEventListener: function () {},
      location: location,
      navigator: navigator
    };
    """

    private func makeContext() -> JSContext {
        let context = JSContext()!
        context.exceptionHandler = { context, exception in context?.exception = exception }
        context.evaluateScript(Self.prelude)
        return context
    }

    @Test func pageScriptBootsAndExposesTheCommandAPI() {
        let context = self.makeContext()
        context.evaluateScript(PlayerScripts.page)

        #expect(context.exception == nil, "page script threw: \(context.exception?.toString() ?? "")")
        #expect(context.evaluateScript("typeof window.__kaset").toString() == "object")
        #expect(context.evaluateScript("__posts.length > 0 && __posts[0].kind").toString() == "boot")
        for command in ["play", "pause", "toggle", "next", "previous", "seek", "state",
                        "playQueueIndex", "removeQueueIndexAsync", "inspectQueue", "health", "shuffle", "repeat", "setInterrupted", "setBackgroundGuard"]
        {
            #expect(
                context.evaluateScript("typeof window.__kaset.\(command)").toString() == "function",
                "missing command \(command)"
            )
        }
    }

    @Test func commandsDegradeGracefullyWithoutADOM() {
        let context = self.makeContext()
        context.evaluateScript(PlayerScripts.page)
        #expect(context.evaluateScript("window.__kaset.toggle()").toString() == "missing:playPause")
        #expect(context.evaluateScript("window.__kaset.seek(10)").toString() == "no-media")
        #expect(context.evaluateScript("typeof window.__kaset.inspectQueue()").toString() == "string")
        #expect(context.exception == nil)
    }

    @Test func healthProbeReportsMissingPartsWithoutADOM() throws {
        let context = self.makeContext()
        context.evaluateScript(PlayerScripts.page)
        let json = try #require(context.evaluateScript("JSON.stringify(window.__kaset.health())").toString())
        #expect(context.exception == nil, "health() threw: \(context.exception?.toString() ?? "")")

        let report = try #require(PlayerHealthReport.parse(json))
        #expect(report.hasTrack == false)
        #expect(report.checks.first?.id == "page")
        #expect(report.checks.first?.status == .ok)
        let byId = Dictionary(uniqueKeysWithValues: report.checks.map { ($0.id, $0) })
        #expect(byId["media"]?.status == .failing)
        #expect(byId["next"]?.status == .failing)
        // Track-only checks wait for a track instead of failing.
        #expect(byId["queue"]?.status == .needsTrack)
        #expect(byId["menu"]?.status == .needsTrack)
        #expect(report.failing.allSatisfy { !$0.needsTrack })
    }

    @Test func injectedScriptsAreSyntacticallyValid() {
        let scripts: [(String, String)] = [
            ("playNext", PlayerScripts.playNext(videoId: "abc", afterVideoId: "def", attempt: 1)),
            ("addToQueue", PlayerScripts.addToQueue(videoId: "abc", attempt: 2)),
            ("watchEndpoint", PlayerScripts.watchEndpointScript(videoId: "abc", playlistId: "RDAMVMabc")),
            ("audioQualityOverride", PlaybackAudioQualityScripts.playbackAudioQualityOverrideScript),
            ("bufferBootstrap", BufferScripts.bootstrap(extended: true)),
            ("audioQualityBootstrap", PlaybackAudioQualityScripts.playbackAudioQualityBootstrapScript(quality: .high)),
        ]
        for (name, source) in scripts {
            let context = JSContext()!
            context.exceptionHandler = { context, exception in context?.exception = exception }
            // `new Function` parses without running it.
            context.evaluateScript("new Function(\(PlayerScripts.literal(source)))")
            #expect(context.exception == nil, "\(name) is not valid JavaScript: \(context.exception?.toString() ?? "")")
        }
    }
}
