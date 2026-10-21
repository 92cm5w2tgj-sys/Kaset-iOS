import JavaScriptCore
import Testing

@testable import KasetiOS

/// Runs the buffer bootstrap in JavaScriptCore against a stand-in `ManagedMediaSource` and `ytcfg`.
struct BufferScriptsTests {
    private static let prelude = """
    function setInterval() { return 0; }
    function clearInterval() {}
    var document = { querySelector: function () { return null; } };
    var window = {};
    function FakeMMS() { this.listeners = {}; }
    FakeMMS.prototype.addEventListener = function (name, f) { (this.listeners[name] = this.listeners[name] || []).push(f); };
    FakeMMS.prototype.fire = function (name) {
      var stopped = false;
      var e = { stopImmediatePropagation: function () { stopped = true; } };
      var list = this.listeners[name] || [];
      var reached = 0;
      for (var i = 0; i < list.length && !stopped; i += 1) { list[i](e); reached += 1; }
      return reached;
    };
    Object.defineProperty(FakeMMS.prototype, 'streaming', { get: function () { return false; }, configurable: true });
    window.ManagedMediaSource = FakeMMS;
    """

    private func context(extended: Bool) -> JSContext {
        let context = JSContext()!
        context.exceptionHandler = { context, exception in context?.exception = exception }
        context.evaluateScript(Self.prelude)
        context.evaluateScript(BufferScripts.bootstrap(extended: extended))
        return context
    }

    @Test func longerBufferHidesWebKitsStopSignal() {
        let context = self.context(extended: true)
        context.evaluateScript("""
        var ms = new window.ManagedMediaSource();
        ms.addEventListener('endstreaming', function () {});   // the page's own listener
        var reached = ms.fire('endstreaming');
        """)
        #expect(context.exception == nil, "\(context.exception?.toString() ?? "")")
        #expect(context.evaluateScript("ms.streaming").toBool() == true)
        #expect(context.evaluateScript("reached").toInt32() == 1, "the page's listener must not run")
        #expect(context.evaluateScript("window.__kasetBuffer.hiddenEndStreaming").toInt32() == 1)
        #expect(context.evaluateScript("ms instanceof FakeMMS").toBool() == true)
    }

    @Test func withoutTheLongerBufferNothingChanges() {
        let context = self.context(extended: false)
        context.evaluateScript("""
        var ms = new window.ManagedMediaSource();
        ms.addEventListener('endstreaming', function () {});
        var reached = ms.fire('endstreaming');
        window.ytcfg = { set: function (o) { this.values = o; } };
        window.ytcfg.set({ WEB_PLAYER_CONTEXT_CONFIGS: { A: { serializedExperimentFlags: 'html5_minimum_readahead_seconds=0.0' } } });
        """)
        #expect(context.exception == nil, "\(context.exception?.toString() ?? "")")
        #expect(context.evaluateScript("ms.streaming").toBool() == false)
        #expect(context.evaluateScript("reached").toInt32() == 2)
        #expect(context.evaluateScript("window.ytcfg.values.WEB_PLAYER_CONTEXT_CONFIGS.A.serializedExperimentFlags").toString()
            == "html5_minimum_readahead_seconds=0.0")
    }

    @Test func onlyTheReadaheadWindowFlagsAreRaised() {
        let context = self.context(extended: true)
        context.evaluateScript("""
        window.ytcfg = { set: function (o) { this.values = o; } };
        window.ytcfg.set({
          WEB_PLAYER_CONTEXT_CONFIGS: { A: { serializedExperimentFlags:
            'html5_minimum_readahead_seconds=0.0&html5_subsegment_readahead_timeout_secs=2.0&html5_maximum_readahead_seconds=0.0' } },
          EXPERIMENT_FLAGS: { html5_platform_minimum_readahead_seconds: 0, html5_subsegment_readahead_min_load_speed: 1.5 }
        });
        """)
        #expect(context.exception == nil, "\(context.exception?.toString() ?? "")")
        #expect(context.evaluateScript("window.ytcfg.values.WEB_PLAYER_CONTEXT_CONFIGS.A.serializedExperimentFlags").toString()
            == "html5_minimum_readahead_seconds=240&html5_subsegment_readahead_timeout_secs=2.0&html5_maximum_readahead_seconds=300")
        #expect(context.evaluateScript("window.ytcfg.values.EXPERIMENT_FLAGS.html5_platform_minimum_readahead_seconds").toInt32() == 240)
        #expect(context.evaluateScript("window.ytcfg.values.EXPERIMENT_FLAGS.html5_subsegment_readahead_min_load_speed").toDouble() == 1.5)
        #expect(context.evaluateScript("typeof window.__kasetBuffer.inspect()").toString() == "string")
    }
}
