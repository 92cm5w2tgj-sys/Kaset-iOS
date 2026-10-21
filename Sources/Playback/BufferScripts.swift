import Foundation

/// Playback buffering preferences.
enum BufferPolicy {
    static let extendedStorageKey = "settings.extendedBuffer"
    static let adaptiveQualityStorageKey = "settings.adaptiveQuality"
    /// How far ahead the longer buffer asks the page to load, in seconds.
    static let extendedReadaheadSeconds = 240

    /// Experimental: keep loading the current track well ahead of the playhead.
    static var isExtended: Bool {
        UserDefaults.standard.bool(forKey: self.extendedStorageKey)
    }

    /// Drop to low audio quality after an underrun (or on a constrained network).
    static var adaptsQuality: Bool {
        UserDefaults.standard.object(forKey: self.adaptiveQualityStorageKey) as? Bool ?? true
    }
}

/// Injected at document start, before YouTube Music's own scripts.
///
/// - Records the page's `MediaSource` / `ManagedMediaSource` objects so the buffer can be
///   inspected. On iPhone WebKit only offers `ManagedMediaSource`, where WebKit itself tells
///   the page when to stop loading (`endstreaming`); that, more than YouTube, caps how far
///   ahead a track is buffered.
/// - With the longer buffer on, those stop signals are hidden from the page (`streaming`
///   reads `true`) and the player's read-ahead window flags are raised.
///
/// Everything is observable through `window.__kasetBuffer.inspect()`.
enum BufferScripts {
    static func bootstrap(extended: Bool) -> String {
        """
        (function () {
          if (window.__kasetBuffer) { return; }
          const READAHEAD = \(BufferPolicy.extendedReadaheadSeconds);
          const info = { sources: [], startStreaming: 0, endStreaming: 0, hiddenEndStreaming: 0, flags: [], overrides: [] };
          window.__kasetBuffer = info;
          window.__kasetExtendedBuffer = \(extended ? "true" : "false");

          // MARK: media sources
          ['ManagedMediaSource', 'MediaSource'].forEach((name) => {
            const Original = window[name];
            if (typeof Original !== 'function') { return; }
            const realStreaming = Object.getOwnPropertyDescriptor(Original.prototype, 'streaming');
            class Tracked extends Original {
              constructor(...args) {
                super(...args);
                info.sources.push({ kind: name, source: this });
                if (info.sources.length > 4) { info.sources.shift(); }
                if (name === 'ManagedMediaSource') {
                  // Registered first, so it runs before the page's own listeners.
                  this.addEventListener('startstreaming', () => { info.startStreaming += 1; });
                  this.addEventListener('endstreaming', (e) => {
                    info.endStreaming += 1;
                    if (window.__kasetExtendedBuffer) { info.hiddenEndStreaming += 1; e.stopImmediatePropagation(); }
                  });
                }
              }
            }
            if (realStreaming && realStreaming.get) {
              Object.defineProperty(Tracked.prototype, 'streaming', {
                configurable: true,
                get() { return window.__kasetExtendedBuffer ? true : realStreaming.get.call(this); }
              });
            }
            try { window[name] = Tracked; } catch (e) {}
          });

          // MARK: read-ahead flags
          // Only the player's own read-ahead window is changed. Names come from a device dump
          // (Inspect buffer): their default 0 means "player default". The many other readahead
          // flags (subsegment timeouts, load-speed thresholds) are tuning knobs, not durations.
          const OVERRIDES = {
            html5_minimum_readahead_seconds: READAHEAD,
            html5_platform_minimum_readahead_seconds: READAHEAD,
            html5_maximum_readahead_seconds: READAHEAD + 60
          };
          const isWatched = (key) => /readahead|readbehind|buffer_health|prefetch|preload|streaming_/i.test(key);
          const note = (key, value) => {
            if (isWatched(key) && info.flags.length < 80) { info.flags.push(key + '=' + value); }
          };
          const raised = (key, value) => {
            if (!window.__kasetExtendedBuffer || !(key in OVERRIDES)) { return null; }
            const n = Number(value);
            const target = OVERRIDES[key];
            if (isFinite(n) && n >= target) { return null; }
            info.overrides.push(key + ': ' + value + ' → ' + target);
            return String(target);
          };
          const patchSerialized = (flags) => {
            if (typeof flags !== 'string') { return flags; }
            return flags.split('&').map((pair) => {
              const i = pair.indexOf('=');
              if (i < 0) { return pair; }
              const key = pair.slice(0, i);
              const value = pair.slice(i + 1);
              note(key, value);
              const next = raised(key, value);
              return next === null ? pair : key + '=' + next;
            }).join('&');
          };
          const patchConfig = (values) => {
            if (!values || typeof values !== 'object') { return; }
            try {
              const players = values.WEB_PLAYER_CONTEXT_CONFIGS;
              if (players && typeof players === 'object') {
                Object.keys(players).forEach((k) => {
                  const c = players[k];
                  if (c && typeof c.serializedExperimentFlags === 'string') {
                    c.serializedExperimentFlags = patchSerialized(c.serializedExperimentFlags);
                  }
                });
              }
              const flags = values.EXPERIMENT_FLAGS;
              if (flags && typeof flags === 'object') {
                Object.keys(flags).forEach((k) => {
                  note(k, flags[k]);
                  const next = raised(k, flags[k]);
                  if (next !== null) { flags[k] = Number(next); }
                });
              }
            } catch (e) { info.overrides.push('error ' + String(e)); }
          };
          // `ytcfg` is created by an inline script; catch it on assignment and wrap `set`.
          const wrap = (cfg) => {
            if (!cfg || cfg.__kasetWrapped || typeof cfg.set !== 'function') { return cfg; }
            const set = cfg.set;
            cfg.set = function (key, value) {
              if (key && typeof key === 'object') { patchConfig(key); } else if (typeof key === 'string') {
                const o = {}; o[key] = value; patchConfig(o);
              }
              return set.apply(this, arguments);
            };
            cfg.__kasetWrapped = true;
            return cfg;
          };
          let current = window.ytcfg;
          try {
            Object.defineProperty(window, 'ytcfg', {
              configurable: true,
              get() { return current; },
              set(v) { current = v; wrap(v); }
            });
          } catch (e) {}
          // Some builds set `ytcfg.set` after the object exists: check again for a while.
          let tries = 0;
          const timer = setInterval(() => { wrap(current); tries += 1; if (tries > 40) { clearInterval(timer); } }, 250);

          // MARK: readout
          info.ahead = () => {
            const m = document.querySelector('video') || document.querySelector('audio');
            if (!m || !m.buffered) { return null; }
            const t = m.currentTime;
            for (let i = 0; i < m.buffered.length; i += 1) {
              if (m.buffered.start(i) <= t + 0.5 && m.buffered.end(i) >= t) { return Math.round(m.buffered.end(i) - t); }
            }
            return 0;
          };
          info.summary = () => {
            const last = info.sources[info.sources.length - 1];
            let streaming = 'n/a';
            if (last && last.kind === 'ManagedMediaSource') {
              try {
                const d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Object.getPrototypeOf(last.source)), 'streaming');
                streaming = d && d.get ? String(d.get.call(last.source)) : '?';
              } catch (e) { streaming = '?'; }
            }
            return (last ? last.kind : 'no media source') + ' streaming=' + streaming
              + ' end=' + info.endStreaming + (window.__kasetExtendedBuffer ? ' (hidden ' + info.hiddenEndStreaming + ')' : '')
              + ' overrides=' + info.overrides.length;
          };
          info.inspect = () => {
            const out = [];
            const m = document.querySelector('video') || document.querySelector('audio');
            out.push('extended=' + window.__kasetExtendedBuffer + ' ahead=' + info.ahead() + 's');
            out.push('summary: ' + info.summary());
            out.push('globals: MediaSource=' + (typeof window.MediaSource) + ' ManagedMediaSource=' + (typeof window.ManagedMediaSource));
            if (m) {
              const ranges = [];
              for (let i = 0; i < m.buffered.length; i += 1) { ranges.push(Math.round(m.buffered.start(i)) + '-' + Math.round(m.buffered.end(i))); }
              out.push('media: t=' + Math.round(m.currentTime) + ' dur=' + Math.round(m.duration) + ' buffered=[' + ranges.join(',') + '] src=' + String(m.currentSrc || m.src).slice(0, 12));
            } else { out.push('media: none'); }
            out.push('overrides: ' + (info.overrides.join(' | ') || 'none'));
            for (let i = 0; i < info.flags.length; i += 8) { out.push('flags: ' + info.flags.slice(i, i + 8).join(' ')); }
            if (!info.flags.length) { out.push('flags: none seen (ytcfg ' + (current ? 'present' : 'absent') + ')'); }
            return out.join('\\n');
          };
        })();
        """
    }
}
