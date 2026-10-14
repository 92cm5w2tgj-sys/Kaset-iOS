import Foundation

/// JavaScript injected into every music.youtube.com document.
///
/// It does three things:
/// 1. reports what the page *really* sees (visibility, media element state) back to Swift,
///    including a 5 s heartbeat so throttling / suspension shows up as gaps;
/// 2. optionally lies about page visibility so the player never learns it is in the background;
/// 3. exposes `window.__spike` so Swift (or the on-screen buttons) can drive playback.
///
/// Selectors for the player bar are the same ones Kaset's macOS app uses.
enum PageScript {
    static func source(spoofVisibility: Bool, autoConfirm: Bool, keepAlive: Bool) -> String {
        template
            .replacingOccurrences(of: "__SPOOF__", with: spoofVisibility ? "true" : "false")
            .replacingOccurrences(of: "__AUTOCONFIRM__", with: autoConfirm ? "true" : "false")
            .replacingOccurrences(of: "__KEEPALIVE__", with: keepAlive ? "true" : "false")
    }

    private static let template = #"""
    (function () {
      if (window.__spike) { return; }
      const SPOOF = __SPOOF__;
      const AUTOCONFIRM = __AUTOCONFIRM__;
      const KEEPALIVE = __KEEPALIVE__;

      const post = (o) => {
        try { o.t = Date.now(); window.webkit.messageHandlers.spike.postMessage(o); } catch (e) {}
      };

      // Capture the real getter before we (maybe) override it.
      const visDesc = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
      const realVis = () => { try { return visDesc.get.call(document); } catch (e) { return 'unknown'; } };

      const media = () => document.querySelector('video') || document.querySelector('audio');
      const title = () => {
        const m = navigator.mediaSession && navigator.mediaSession.metadata;
        if (m && m.title) { return m.title; }
        const el = document.querySelector('ytmusic-player-bar .title');
        return el ? el.textContent.trim() : null;
      };
      const snapshot = () => {
        const m = media();
        return {
          paused: m ? m.paused : null,
          ended: m ? m.ended : null,
          currentTime: m ? Math.round(m.currentTime * 10) / 10 : null,
          duration: (m && isFinite(m.duration)) ? Math.round(m.duration) : null,
          readyState: m ? m.readyState : null,
          vis: realVis(),
          title: title(),
          path: location.pathname + location.search.slice(0, 40)
        };
      };

      if (SPOOF) {
        const def = (proto, prop, value) => {
          try { Object.defineProperty(proto, prop, { configurable: true, get: () => value }); } catch (e) {}
        };
        def(Document.prototype, 'hidden', false);
        def(Document.prototype, 'visibilityState', 'visible');
        def(Document.prototype, 'webkitHidden', false);
        def(Document.prototype, 'webkitVisibilityState', 'visible');
        try { document.hasFocus = () => true; } catch (e) {}
        window.addEventListener('blur', (e) => e.stopImmediatePropagation(), true);
      }

      // Registered first, on window/capture, so it also runs before the page's own listeners.
      window.addEventListener('visibilitychange', (e) => {
        post(Object.assign({ kind: 'vis', spoofed: SPOOF }, snapshot()));
        if (SPOOF) { e.stopImmediatePropagation(); }
      }, true);

      ['play', 'playing', 'pause', 'ended', 'waiting', 'stalled', 'error', 'emptied'].forEach((ev) => {
        document.addEventListener(ev, (e) => {
          const t = e.target;
          if (t && t.tagName && /^(VIDEO|AUDIO)$/.test(t.tagName)) {
            post(Object.assign({ kind: 'media', ev: ev }, snapshot()));
          }
        }, true);
      });

      setInterval(() => post(Object.assign({ kind: 'hb' }, snapshot())), 5000);

      if (AUTOCONFIRM) {
        // Best effort: YouTube Music sometimes asks "Continue listening?" after a long session.
        setInterval(() => {
          const dlg = document.querySelector('ytmusic-you-there-renderer, yt-confirm-dialog-renderer');
          if (!dlg || dlg.offsetParent === null) { return; }
          const b = dlg.querySelector('#confirm-button');
          post({ kind: 'dialog', tag: dlg.tagName.toLowerCase(), clicked: !!b });
          if (b) { b.click(); }
        }, 4000);
      }

      const click = (sel) => {
        const b = document.querySelector(sel);
        if (!b) { return 'missing:' + sel; }
        b.click();
        return 'clicked';
      };

      // Lock screen: WebKit derives the remote commands from the page's Media Session handlers.
      // YouTube Music leaves next/previous unset in this context, so iOS falls back to ±10 s.
      // Own those handlers, and neutralise any seek handlers the page tries to register.
      (function () {
        const ms = navigator.mediaSession;
        if (!ms || !ms.setActionHandler) { return; }
        const orig = ms.setActionHandler.bind(ms);
        const ours = {
          nexttrack: () => { post({ kind: 'ms', action: 'nexttrack' }); click('.next-button.ytmusic-player-bar'); },
          previoustrack: () => { post({ kind: 'ms', action: 'previoustrack' }); click('.previous-button.ytmusic-player-bar'); }
        };
        const apply = () => {
          try {
            orig('nexttrack', ours.nexttrack);
            orig('previoustrack', ours.previoustrack);
            orig('seekforward', null);
            orig('seekbackward', null);
          } catch (e) { post({ kind: 'ms', action: 'apply-failed', msg: String(e) }); }
        };
        ms.setActionHandler = (name, handler) => {
          if (name === 'nexttrack' || name === 'previoustrack') { return; }
          if (name === 'seekforward' || name === 'seekbackward') { return orig(name, null); }
          return orig(name, handler);
        };
        apply();
        post({ kind: 'ms', action: 'applied' });
        document.addEventListener('playing', apply, true);
        setInterval(apply, 5000);
      })();

      if (KEEPALIVE) {
        // Same idea as Kaset's ADR-0036: an inaudible Web Audio graph. Here the goal is different:
        // give WebKit a reason not to freeze the WebContent process while playback is paused.
        let ctx = null;
        const ensure = () => {
          try {
            if (!ctx) {
              const AC = window.AudioContext || window.webkitAudioContext;
              ctx = new AC();
              const gain = ctx.createGain();
              gain.gain.value = 0.00001;
              const osc = ctx.createOscillator();
              osc.frequency.value = 20;
              osc.connect(gain);
              gain.connect(ctx.destination);
              osc.start();
              ctx.onstatechange = () => post({ kind: 'ka', state: ctx.state });
            }
            if (ctx.state !== 'running') { ctx.resume().catch(() => {}); }
            post({ kind: 'ka', state: ctx.state });
          } catch (e) { post({ kind: 'ka', state: 'error ' + String(e) }); }
        };
        document.addEventListener('playing', ensure, true);
        document.addEventListener('pause', () => { if (ctx && ctx.state !== 'running') { ctx.resume().catch(() => {}); } }, true);
      }

      window.__spike = {
        snapshot: snapshot,
        play: () => {
          const m = media();
          if (!m) { return 'no-media'; }
          const p = m.play();
          if (p && p.catch) { p.catch((err) => post({ kind: 'playerr', msg: String(err) })); }
          return 'play()';
        },
        pause: () => { const m = media(); if (!m) { return 'no-media'; } m.pause(); return 'pause()'; },
        toggle: () => click('.play-pause-button.ytmusic-player-bar'),
        next: () => click('.next-button.ytmusic-player-bar'),
        prev: () => click('.previous-button.ytmusic-player-bar')
      };

      post(Object.assign({ kind: 'boot', spoof: SPOOF }, snapshot()));
    })();
    """#
}
