import Foundation

/// JavaScript for the playback page (`music.youtube.com`, full desktop player, hidden 1×1).
///
/// Evolved from the spike's `PageScript` (see `docs/spike-findings.md`): same Media Session
/// ownership and keep-alive, plus a structured `state` message the native side mirrors.
/// Player-bar selectors come from kaset `SingletonPlayerWebView+ObserverScript.swift`.
enum PlayerScripts {
    static let bridgeName = "kaset"

    static func literal(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    /// Locates the slotted player bar and its parts (kaset `playerBarLookupFunctionJS`).
    static let playerBarLookup = """
    const __kasetPlayerBarSelectors = {
        title: '.ytmusic-player-bar.title, .ytmusicTrackInfoTitle',
        byline: '.ytmusic-player-bar.byline, .ytmusicTrackInfoByline',
        thumbnail: '.ytmusic-player-bar .thumbnail img, ytmusic-player-bar .image, img.ytmusicTrackInfoThumbnail',
        playPause: '.play-pause-button.ytmusic-player-bar, .ytmusicPlayerControlsPlayPauseButton button',
        next: '.next-button.ytmusic-player-bar, .ytmusicPlayerControlsNextButton button',
        previous: '.previous-button.ytmusic-player-bar, .ytmusicPlayerControlsPreviousButton button',
        menu: '.middle-controls-buttons.ytmusic-player-bar ytmusic-menu-renderer button, '
            + '.ytMusicMiniPlayerMenuButton button',
        likeRenderer: 'ytmusic-like-button-renderer',
        likeButton: 'like-button-view-model button',
        dislikeButton: 'dislike-button-view-model button'
    };
    function __kasetPlayerBar() {
        return document.querySelector('[slot="player-bar"]');
    }
    function __kasetPlayerBarElement(name, playerBar = __kasetPlayerBar()) {
        return playerBar ? playerBar.querySelector(__kasetPlayerBarSelectors[name]) : null;
    }
    """

    /// Injected at document start into every document of the playback web view.
    static var page: String {
        """
        (function () {
          if (window.__kaset) { return; }
          \(self.playerBarLookup)

          const post = (o) => {
            try { o.t = Date.now(); window.webkit.messageHandlers.\(self.bridgeName).postMessage(o); } catch (e) {}
          };
          const visDesc = Object.getOwnPropertyDescriptor(Document.prototype, 'visibilityState');
          const realVis = () => { try { return visDesc.get.call(document); } catch (e) { return 'unknown'; } };
          const media = () => document.querySelector('video') || document.querySelector('audio');
          // The slotted-bar lookup (kaset) is tried first; the spike's plain selectors and the
          // player API are fallbacks so controls keep working if the DOM shape differs.
          const legacy = {
            playPause: '.play-pause-button.ytmusic-player-bar',
            next: '.next-button.ytmusic-player-bar',
            previous: '.previous-button.ytmusic-player-bar'
          };
          const control = (name) => {
            let b = null;
            try { b = __kasetPlayerBarElement(name); } catch (e) {}
            if (!b && legacy[name]) { b = document.querySelector(legacy[name]); }
            return b;
          };
          const playerApi = () => {
            const p = document.querySelector('ytmusic-player');
            if (p && p.playerApi) { return p.playerApi; }
            return document.getElementById('movie_player');
          };
          const click = (name) => {
            const b = control(name);
            if (b) { b.click(); return 'clicked'; }
            const m = media();
            const api = playerApi();
            try {
              if (name === 'playPause' && m) { if (m.paused) { m.play(); } else { m.pause(); } return 'media-toggle'; }
              if (name === 'next' && api && api.nextVideo) { api.nextVideo(); return 'api-next'; }
              if (name === 'previous' && api && api.previousVideo) { api.previousVideo(); return 'api-previous'; }
            } catch (e) { return 'error:' + String(e); }
            return 'missing:' + name;
          };
          const enabled = (name) => {
            const b = control(name);
            if (!b) { return true; }
            return !b.disabled && b.getAttribute('aria-disabled') !== 'true';
          };

          const videoId = () => {
            try {
              const p = document.querySelector('ytmusic-player');
              if (p && p.playerApi && typeof p.playerApi.getVideoData === 'function') {
                const d = p.playerApi.getVideoData();
                const id = d && (d.video_id || d.videoId);
                if (id) { return id; }
              }
            } catch (e) {}
            try {
              const m = document.getElementById('movie_player');
              if (m && typeof m.getVideoData === 'function') {
                const d = m.getVideoData();
                const id = d && (d.video_id || d.videoId);
                if (id) { return id; }
              }
            } catch (e) {}
            return new URLSearchParams(location.search).get('v');
          };

          const metadata = () => {
            const m = navigator.mediaSession && navigator.mediaSession.metadata;
            if (!m) { return { title: null, artist: null, album: null, artwork: null }; }
            const art = m.artwork || [];
            return {
              title: m.title || null,
              artist: m.artist || null,
              album: m.album || null,
              artwork: art.length ? art[art.length - 1].src : null
            };
          };

          const text = (el, sel) => {
            const n = el.querySelector(sel);
            return n ? n.textContent.trim() : '';
          };
          const queue = () => {
            const items = Array.from(document.querySelectorAll('ytmusic-player-queue-item'));
            return items.slice(0, 200).map((el) => {
              const d = el.data || el.__data || {};
              const current = el.hasAttribute('selected')
                || el.hasAttribute('is-playlist-panel-video-renderer-selected')
                || el.getAttribute('aria-current') === 'true';
              return {
                videoId: (d && d.videoId) || '',
                title: text(el, '.song-title'),
                artist: text(el, '.byline'),
                current: current
              };
            });
          };

          let lastQueueKey = '';
          const state = (ev, withQueue) => {
            const m = media();
            const meta = metadata();
            const out = {
              kind: 'state', ev: ev,
              paused: m ? m.paused : null,
              ended: m ? m.ended : null,
              currentTime: m ? Math.round(m.currentTime * 10) / 10 : null,
              duration: (m && isFinite(m.duration)) ? Math.round(m.duration * 10) / 10 : null,
              videoId: videoId(),
              title: meta.title, artist: meta.artist, album: meta.album, artwork: meta.artwork,
              canNext: enabled('next'), canPrevious: enabled('previous'),
              vis: realVis()
            };
            if (withQueue) {
              const q = queue();
              const key = JSON.stringify(q.map((e) => e.videoId + (e.current ? '*' : '')));
              if (key !== lastQueueKey) { lastQueueKey = key; out.queue = q; }
            }
            return out;
          };

          ['play', 'playing', 'pause', 'ended', 'waiting', 'stalled', 'error', 'emptied', 'loadedmetadata', 'seeked'].forEach((ev) => {
            document.addEventListener(ev, (e) => {
              const t = e.target;
              if (t && t.tagName && /^(VIDEO|AUDIO)$/.test(t.tagName)) {
                post(state(ev, ev === 'playing' || ev === 'loadedmetadata' || ev === 'emptied'));
              }
            }, true);
          });
          window.addEventListener('visibilitychange', () => {
            post(state('visibilitychange', false));
            keepAlive();
          }, true);

          // Position/heartbeat: 2 s while playing, 5 s otherwise. Gaps in these are how
          // throttling or suspension shows up natively.
          let lastBeat = 0;
          setInterval(() => {
            const m = media();
            const playing = !!m && !m.paused;
            const now = Date.now();
            if (now - lastBeat < (playing ? 1900 : 4900)) { return; }
            lastBeat = now;
            post(Object.assign(state('hb', true), { kind: 'state', hb: true }));
          }, 1000);

          // Best effort: "Continue listening?" after a long session.
          setInterval(() => {
            const dlg = document.querySelector('ytmusic-you-there-renderer, yt-confirm-dialog-renderer');
            if (!dlg || dlg.offsetParent === null) { return; }
            const b = dlg.querySelector('#confirm-button');
            post({ kind: 'dialog', tag: dlg.tagName.toLowerCase(), clicked: !!b });
            if (b) { b.click(); }
          }, 4000);

          // Lock screen: own next/previous, neutralise ±10 s seek handlers.
          (function () {
            const ms = navigator.mediaSession;
            if (!ms || !ms.setActionHandler) { return; }
            const orig = ms.setActionHandler.bind(ms);
            const ours = {
              nexttrack: () => { post({ kind: 'ms', action: 'nexttrack' }); click('next'); },
              previoustrack: () => { post({ kind: 'ms', action: 'previoustrack' }); click('previous'); }
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
            document.addEventListener('playing', apply, true);
            setInterval(apply, 5000);
          })();

          // Keep the page alive while paused: an inaudible AudioContext that is never torn
          // down and is resumed whenever it is interrupted/suspended (spike findings §2).
          let ctx = null;
          function keepAlive() {
            try {
              if (!ctx) {
                const AC = window.AudioContext || window.webkitAudioContext;
                if (!AC) { return; }
                ctx = new AC();
                const gain = ctx.createGain();
                gain.gain.value = 0.00001;
                const osc = ctx.createOscillator();
                osc.frequency.value = 20;
                osc.connect(gain);
                gain.connect(ctx.destination);
                osc.start();
                ctx.onstatechange = () => {
                  post({ kind: 'ka', state: ctx.state });
                  if (ctx.state === 'interrupted' || ctx.state === 'suspended') { ctx.resume().catch(() => {}); }
                };
              }
              if (ctx.state !== 'running') { ctx.resume().catch(() => {}); }
            } catch (e) { post({ kind: 'ka', state: 'error ' + String(e) }); }
          }
          document.addEventListener('playing', keepAlive, true);
          document.addEventListener('pause', keepAlive, true);

          window.__kaset = {
            state: () => state('poll', true),
            play: () => {
              const m = media();
              if (!m) { return 'no-media'; }
              const p = m.play();
              if (p && p.catch) { p.catch((err) => post({ kind: 'playerr', msg: String(err) })); }
              return 'play()';
            },
            pause: () => { const m = media(); if (!m) { return 'no-media'; } m.pause(); return 'pause()'; },
            toggle: () => click('playPause'),
            next: () => click('next'),
            previous: () => click('previous'),
            seek: (t) => { const m = media(); if (!m) { return 'no-media'; } m.currentTime = t; return 'seek'; }
          };
          post({ kind: 'boot', path: location.pathname + location.search.slice(0, 40), vis: realVis() });
        })();
        """
    }
}
