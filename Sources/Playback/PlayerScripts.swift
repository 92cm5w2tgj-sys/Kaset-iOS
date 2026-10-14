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
        return document.querySelector('[slot="player-bar"]') || document.querySelector('ytmusic-player-bar');
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
          // Same reading as kaset's queue injection: the video id sits at a varying depth.
          const firstVideoId = (root) => {
            const seen = new Set();
            const visit = (value, depth) => {
              if (!value || typeof value !== 'object' || depth > 7 || seen.has(value)) { return ''; }
              seen.add(value);
              for (const [key, child] of Object.entries(value)) {
                if ((key === 'videoId' || key === 'video_id') && typeof child === 'string' && child) { return child; }
              }
              for (const child of Object.values(value)) {
                const found = visit(child, depth + 1);
                if (found) { return found; }
              }
              return '';
            };
            return visit(root, 0);
          };
          const QUEUE_ITEMS = 'ytmusic-player-queue-item, ytmusic-player-queue-item-renderer, '
            + 'ytmusic-player-queue ytmusic-responsive-list-item-renderer';
          const queueItemIsCurrent = (el) => {
            if (el.__kasetIsCurrent === true) { return true; }
            if (el.hasAttribute('selected') || el.hasAttribute('is-playlist-panel-video-renderer-selected')) { return true; }
            const aria = el.getAttribute('aria-current');
            if (aria === 'true' || aria === 'page') { return true; }
            return el.classList.contains('selected');
          };
          const queue = () => {
            const items = Array.from(document.querySelectorAll(QUEUE_ITEMS));
            return items.slice(0, 200).map((el) => ({
              videoId: firstVideoId(el.data || el.__data || null),
              title: text(el, '.song-title') || text(el, 'yt-formatted-string.title'),
              artist: text(el, '.byline') || text(el, 'yt-formatted-string.byline'),
              current: queueItemIsCurrent(el)
            }));
          };

          // Shuffle / repeat live on the player bar. Selectors and attributes are best effort.
          const barEl = () => document.querySelector('ytmusic-player-bar');
          const shuffleButton = () => { const b = barEl(); return b ? b.querySelector('.shuffle') : null; };
          const repeatButton = () => { const b = barEl(); return b ? b.querySelector('.repeat') : null; };
          const shuffleOn = () => {
            const b = shuffleButton();
            if (!b) { return null; }
            return b.getAttribute('aria-pressed') === 'true' || b.hasAttribute('active') || b.classList.contains('active');
          };
          const repeatMode = () => {
            const b = barEl();
            const raw = b ? (b.getAttribute('repeat-mode_') || b.getAttribute('repeat-mode') || '') : '';
            const v = raw.toUpperCase();
            return v === 'ALL' ? 'all' : (v === 'ONE' ? 'one' : 'off');
          };

          \(AdDetectionScript.detection)
          window.__kasetAdAutoSkip = \(AdSkip.isEnabled ? "true" : "false");
          const adNow = () => { try { return !!isAdShowing(); } catch (e) { return false; } };

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
              listId: new URLSearchParams(location.search).get('list'),
              title: meta.title, artist: meta.artist, album: meta.album, artwork: meta.artwork,
              canNext: enabled('next'), canPrevious: enabled('previous'),
              shuffle: shuffleOn(), repeat: repeatMode(), ad: adNow(),
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

          // Optional ad skipping: when an ad is playing and the setting is on, press next (the
          // page then moves past the ad). A fallback seeks the ad to its end. Rate limited so a
          // wrong detection can never skip more than one item every few seconds.
          let lastAdSkip = 0;
          const skipAdIfNeeded = () => {
            if (!window.__kasetAdAutoSkip || !adNow()) { return; }
            const now = Date.now();
            if (now - lastAdSkip < 4000) { return; }
            lastAdSkip = now;
            const skipButton = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
            if (skipButton) { skipButton.click(); post({ kind: 'ad', via: 'skip-button' }); return; }
            const result = click('next');
            if (result === 'clicked') { post({ kind: 'ad', via: 'next' }); return; }
            const m = media();
            if (m && isFinite(m.duration) && m.duration > 0) {
              m.currentTime = m.duration;
              post({ kind: 'ad', via: 'seek-end' });
            }
          };
          setInterval(skipAdIfNeeded, 500);
          document.addEventListener('playing', skipAdIfNeeded, true);

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
            // Queue editing goes through the page's own queue items (selectors best effort).
            playQueueIndex: (i) => {
              const items = Array.from(document.querySelectorAll(QUEUE_ITEMS));
              const el = items[i];
              if (!el) { return 'missing:queue-item'; }
              const play = el.querySelector('ytmusic-play-button-renderer') || el;
              play.click();
              return 'clicked';
            },
            removeQueueIndex: (i) => {
              const items = Array.from(document.querySelectorAll(QUEUE_ITEMS));
              const el = items[i];
              if (!el) { return 'missing:queue-item'; }
              const menuButton = el.querySelector('ytmusic-menu-renderer button, ytmusic-menu-renderer tp-yt-paper-icon-button');
              if (!menuButton) { return 'missing:menu'; }
              menuButton.click();
              let tries = 0;
              const timer = setInterval(() => {
                tries += 1;
                const entries = Array.from(document.querySelectorAll('ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer'));
                const target = entries.find((e) => /remove from queue|retirer de la file|remove/i.test(e.textContent || ''));
                if (target) { clearInterval(timer); target.click(); return; }
                if (tries > 20) { clearInterval(timer); document.body.click(); }
              }, 100);
              return 'menu-opened';
            },
            // Awaitable removal used by queue editing: opens the entry's own menu, presses
            // "Remove from queue" and resolves once the queue shrank. On failure the result
            // carries what was found, so the app can show *why*.
            removeQueueIndexAsync: (i) => new Promise((resolve) => {
              const items = Array.from(document.querySelectorAll(QUEUE_ITEMS));
              const before = items.length;
              const el = items[i];
              if (!el) { return resolve('missing:queue-item(' + i + '/' + before + ')'); }

              const describe = (n) => n ? (n.tagName.toLowerCase() + (n.className ? '.' + String(n.className).split(' ').join('.') : '')) : 'none';
              const candidates = [
                'ytmusic-menu-renderer button',
                'ytmusic-menu-renderer tp-yt-paper-icon-button',
                'ytmusic-menu-renderer yt-icon-button',
                'ytmusic-menu-renderer',
                '[aria-label*="menu" i]',
                '[aria-label*="action" i]',
                '.menu button',
                '.menu'
              ];
              let menuButton = null;
              for (const sel of candidates) {
                menuButton = el.querySelector(sel);
                if (menuButton) { break; }
              }
              if (!menuButton) {
                return resolve('missing:menu in ' + describe(el) + ' children=' +
                  Array.from(el.children).map(describe).join(',').slice(0, 140));
              }
              // Menus can be hidden until hover/selection; make the row "active" first.
              try { el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true })); } catch (e) {}
              menuButton.click();

              const isRemoveEntry = (e) => {
                try {
                  const d = e.data || e.__data || null;
                  if (d && JSON.stringify(d).indexOf('removeFromQueue') !== -1) { return true; }
                } catch (err) {}
                return /remove from queue|retirer de la file|remove|supprimer|retirer|quitar|entfernen/i.test(e.textContent || '');
              };

              let tries = 0;
              const poll = setInterval(() => {
                tries += 1;
                const entries = Array.from(document.querySelectorAll(
                  'ytmusic-menu-popup-renderer ytmusic-menu-service-item-renderer, '
                  + 'tp-yt-paper-listbox ytmusic-menu-service-item-renderer, '
                  + 'ytmusic-menu-service-item-renderer'
                ));
                const target = entries.find(isRemoveEntry);
                if (target) {
                  clearInterval(poll);
                  target.click();
                  let checks = 0;
                  const verify = setInterval(() => {
                    checks += 1;
                    if (document.querySelectorAll(QUEUE_ITEMS).length < before) {
                      clearInterval(verify);
                      resolve('removed');
                    } else if (checks > 30) {
                      clearInterval(verify);
                      resolve('readback-timeout(' + before + ')');
                    }
                  }, 100);
                } else if (tries > 25) {
                  clearInterval(poll);
                  try { document.body.click(); } catch (e) {}
                  resolve('menu-timeout entries=[' +
                    entries.map((e) => (e.textContent || '').trim().slice(0, 18)).join('|').slice(0, 120) + ']');
                }
              }, 100);
            }),
            shuffle: () => { const b = shuffleButton(); if (!b) { return 'missing:shuffle'; } b.click(); return 'clicked'; },
            repeat: () => { const b = repeatButton(); if (!b) { return 'missing:repeat'; } b.click(); return 'clicked'; },
            seek: (t) => {
              const api = playerApi();
              try {
                if (api && typeof api.seekTo === 'function') { api.seekTo(t, true); return 'api-seek'; }
              } catch (e) {}
              const m = media();
              if (!m) { return 'no-media'; }
              m.currentTime = t;
              return 'media-seek';
            }
          };
          post({ kind: 'boot', path: location.pathname + location.search.slice(0, 40), vis: realVis() });
        })();
        """
    }
}
