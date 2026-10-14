# iOS background-playback spike — findings

Throwaway app, not in this repo (it lived in `~/Desktop/Developer/YoutubeMusic Spik`).
Everything needed to re-create it is below. Physical iPhone, Premium and logged-out
accounts, tests of 5–10 minutes.

## Results

| Question | Result | Evidence |
|---|---|---|
| Does a `WKWebView` keep playing with the screen locked? | **Yes** | Heartbeats every 5 s with `vis=hidden`, `maxJSGap=6s`, `nativeTicks` regular |
| Does the playlist advance by itself in the background? | **Yes** | `tracks=3..4`, `ended=1..2` per background session; track titles change while `vis=hidden` |
| Does it work with the hidden 1×1 web view (Kaset's layout)? | **Yes** | Confirmed by the user |
| Premium vs logged-out | Both work | Confirmed by the user |
| Lock-screen next / previous | **No by default** (shows ±10 s), **yes** with page-level `mediaSession` handlers | `[remote] mediaSession nexttrack/previoustrack` reach the page |
| Pause from lock screen, wait, press play | **Fails** without keep-alive: WebContent frozen 152 s, Now Playing widget cleared, stream stalls at the same second then `emptied`. **Works** with keep-alive | App process stayed alive (`nativeTicks=36`, `maxNativeGap=5s`) while page heartbeats stopped; with keep-alive 160 s of heartbeats during pause and play resumes |
| Google sign-in in the web view | Fails with desktop macOS UA ("Something went wrong"); works with Mobile Safari UA | User report |
| `spoofVisibility`, `resumeOnBackground` workarounds | Not needed | Playback and queue advance worked with both off |
| Native `MPRemoteCommandCenter` play/pause (experiment B) | **Inconclusive, not needed** | No `[remote] native …` lines in the supplied log |

## Extended run (13 min, screen locked, 21 tracks)

`bg=782s`, `tracks=21`, `ended=3`, `hb=131`, `maxJSGap=6s`, `nativeTicks=153`, `maxNativeGap=5s`.
Rapid lock-screen next presses (≈2 s apart) each advanced the track. Playback, queue
advance and lock-screen next/previous are solid over this duration.

One failure, reproducible by this sequence: **pause in the foreground → immediately lock/background**.
`AudioContext` went `interrupted` on `didEnterBackground`, no `pause` event followed (it had
already fired in the foreground), so nothing re-resumed it, and the whole app was suspended:
`[native] GAP 144s (app was suspended)`, `[js] GAP 145s`. When the pause happened while already
in the background, the page's `pause` listener resumed the context (`interrupted → running`)
and everything stayed alive. Hypothesis (untested): resume the context from `statechange` and
`visibilitychange` as well, not only from `playing`/`pause`.

Ads: both times the media pause fired at `didEnterBackground` (`vis=hidden`) the item playing
was an ad (6 s and 30 s creatives); regular tracks never paused on backgrounding. Ads appear to
require a visible page.

## What to carry into the app

### 1. Audio session

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [])
try session.setActive(true)
```

Info.plist: `UIBackgroundModes = [audio]`.

### 2. Keep the page alive while paused (inaudible AudioContext)

Started from the media `playing` event and never torn down while a session is active:

```js
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
    }
    if (ctx.state !== 'running') { ctx.resume().catch(() => {}); }
  } catch (e) {}
};
document.addEventListener('playing', ensure, true);
document.addEventListener('pause', () => { if (ctx && ctx.state !== 'running') { ctx.resume().catch(() => {}); } }, true);
```

Needed in addition, **not yet validated** (see "Extended run"): re-resume when the context
becomes `interrupted`/`suspended` and when the page becomes hidden:

```js
ctx.onstatechange = () => {
  if (ctx.state === 'interrupted' || ctx.state === 'suspended') { ctx.resume().catch(() => {}); }
};
window.addEventListener('visibilitychange', ensure, true);
```

Observed: the context goes `interrupted` when the app enters the background and returns
to `running` when playback pauses; that was enough to keep heartbeats flowing.

Note the macOS app already has an output-continuity `AudioContext` (ADR-0036) that is
released on pause. The iOS variant must **not** release it on pause.

### 3. Lock-screen next / previous

```js
const ms = navigator.mediaSession;
const orig = ms.setActionHandler.bind(ms);
const ours = {
  nexttrack: () => click('.next-button.ytmusic-player-bar'),
  previoustrack: () => click('.previous-button.ytmusic-player-bar'),
};
const apply = () => {
  orig('nexttrack', ours.nexttrack);
  orig('previoustrack', ours.previoustrack);
  orig('seekforward', null);
  orig('seekbackward', null);
};
ms.setActionHandler = (name, handler) => {
  if (name === 'nexttrack' || name === 'previoustrack') { return; }   // keep ours
  if (name === 'seekforward' || name === 'seekbackward') { return orig(name, null); }
  return orig(name, handler);
};
apply();
document.addEventListener('playing', apply, true);
setInterval(apply, 5000);
```

For the real app, prefer routing next/previous through `PlayerService` (queue-aware)
over clicking the page's buttons; the click approach is what the spike proved.

### 4. User agents

| Use | User agent |
|---|---|
| Playback (existing `WebKitManager.userAgent`) | `Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15` |
| Google sign-in | Default iOS WebKit UA with `applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"` |

Cookies are shared through the persistent `WKWebsiteDataStore`, so signing in with the
mobile UA and then playing with the desktop UA worked in the spike.

### 5. Diagnostics worth keeping in the app (debug builds)

- 5 s JS heartbeat + 5 s native ticker; a gap > 12 s on either side is logged.
- Log `didEnterBackground` / `willEnterForeground` / `deviceLocking`.
- Log `webViewWebContentProcessDidTerminate`.
- Log `AVAudioSession` interruption begin/end and route changes.
- File log in `Documents/` flushed per line (survives a kill).

## Not verified

- Sessions longer than ~10 minutes; battery cost of the permanent `AudioContext`.
- Behaviour under memory pressure / `WEBCONTENT PROCESS TERMINATED`.
- Phone call, Bluetooth/AirPods connect-disconnect, network handover.
- Whether Kaset's native `NowPlayingManager` can own lock-screen metadata on iOS.
- The `ytmusic-you-there-renderer` "continue listening?" auto-confirm selector (guessed).
