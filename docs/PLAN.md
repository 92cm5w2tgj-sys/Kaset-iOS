# Kaset iOS — plan

Status lives in [`TRACKER.md`](TRACKER.md). Evidence for the playback approach:
[`spike-findings.md`](spike-findings.md).

**Goal:** a native (SwiftUI) iOS YouTube Music client, sideloaded, that keeps playing with
the screen locked, advances through the queue in the background, and is controllable from
the lock screen / Control Center / AirPods.

**History.** Step 0 was a throwaway spike (this repo's first commits). A first port attempt
(S1–S5) compiled the macOS app's shared sources for iOS on branch `feat/ios-port` of
`emoonadev/kaset`; it was abandoned because the macOS player stack is too entangled and the
spike's small web view played better. That branch stays as a reference only. **This repo is
now the app.** The macOS app (`~/Desktop/Developer/kaset`, `main`) is the reference for
endpoints, parsers, models and the auth contract — sources are *copied*, not shared.

## Reference: the kaset macOS app

Source of truth for how YouTube Music is actually called and parsed. **Read it when you need
to understand something instead of guessing** — response shapes are undocumented and change
without notice. Repo: `/Users/mickaelbelhassen/Desktop/Developer/kaset` (branch `main`;
`feat/ios-port` holds the abandoned port, useful for the iOS-only scripts). Upstream:
`sozercan/kaset`, fork `emoonadev/kaset`. Paths below are relative to that repo.

| Need | Where |
|---|---|
| Project rules, API discovery workflow, secrets policy | `AGENTS.md` (CLAUDE.md) |
| Architecture overview, playback overview | `docs/architecture.md`, `docs/playback.md` |
| **Live endpoint exploration** (run it, don't infer) | `swift run api-explorer` — `Sources/APIExplorer/main.swift`, `docs/api-discovery.md`; commands: `auth`, `list`, `browse FEmusic_home -v` |
| InnerTube client: request body, headers, `SAPISIDHASH`, brand/auth-user, error mapping (`authExpired` on 401/403), caching | `Sources/Kaset/Services/API/YTMusicClient.swift`, `InnerTubeSupport.swift`, `APISessionConfiguration.swift`, `APICache.swift` |
| Parsers (Home, Search + suggestions, Playlist, Artist, Library, Radio queue, Song metadata, Lyrics, Accounts) | `Sources/Kaset/Services/API/Parsers/*` (modular design: `docs/adr/0003-modular-api-parsers.md`) |
| Models (Song, Playlist, Album, Artist, HomeSection, SearchResponse, MoodCategory, LikeStatus…) | `Sources/Kaset/Models/*` |
| Parser tests and **sanitized fixtures** | `Tests/KasetTests/` (e.g. `YTMusicClientTests`, `*ParserTests`, `Fixtures`) |
| Auth: cookie archive, restore, Keychain, sign-out clearing, login attempts, passkey suppression | `Services/WebKit/WebKitManager*.swift`, `Services/Auth/AuthService.swift`, `AccountService.swift`, `LoginPasskeySuppression.swift`, `Views/LoginSheet.swift`, `Views/LoginWebView.swift`; ADR `0033-login-passkey-suppression.md`; account switching `0023-brand-account-history-session-switch.md` |
| Playback bridge: page scripts, event payloads, queue injection, ad detection, volume, media-session override | `Views/SingletonPlayerWebView+*.swift`, `Views/MiniPlayerWebView.swift`, `Services/WebKit/PlaybackAdDetectionScript.swift`, `Services/Player/WebPlaybackAudioOutput.swift`; ADRs `0001-webview-playback`, `0026-generation-scoped-web-playback-bridge`, `0034-replace-playback-navigation`, `0035-gapless-playback-native-queue`, `0036-*` (output continuity) |
| Player/queue semantics (what "play next", shuffle, smart shuffle, queue identity mean) | `Services/Player/PlayerService*.swift`, ADRs `0025-smart-shuffle`, `0027-native-music-playback-intents-and-queue-entry-identity` |
| Now Playing / remote commands | `Services/Player/NowPlayingManager.swift` |
| Existing screens to mirror (Home, Explore, Charts, Moods, New releases, Library, History, Playlist/Artist detail, Queue, Lyrics) | `Sources/Kaset/Views/*View.swift`, `ViewModels/*` |
| Settings keys and defaults | `Services/SettingsManager.swift` |
| Localization (catalog is the source of truth) | `Sources/Kaset/Resources/Localizable.xcstrings` |
| Common concurrency / lifecycle pitfalls, diagnostics template | `docs/common-bug-patterns.md` |
| What was learned porting the macOS code to iOS | `feat/ios-port`: `docs/ios/TRACKER.md` (log), `Sources/KasetiOS/Playback/IOSPlaybackScripts.swift`, `AudioSessionController.swift`, the `#if os(iOS)` blocks in `WebKitManager.swift` |
| The spike's own evidence | [`spike-findings.md`](spike-findings.md) |

How to use it: **copy** what a step needs (trimming macOS/AppKit, video, AI, scrobbling,
extensions), keep the original type names so a later diff against kaset stays readable, and
note the source path + commit in the file header. Do not add kaset as a dependency and do not
edit it from here.

## Ground rules

1. **One step at a time**, each ending on a gate: build green on a real iPhone, a short
   verification checklist, then the user confirms. No step starts before the previous is ✅.
2. **When unsure how something works, read kaset first** (see *Reference* above), and verify
   any endpoint with `swift run api-explorer` before writing a parser.
3. **Never put secrets in code, logs or fixtures** (cookies, SAPISID, tokens). Fixtures are
   sanitized captures; placeholders only.
4. **API over WebView.** Everything except audio playback and sign-in goes through the
   InnerTube client. The web view is the playback engine only.
5. **Measure, don't guess** for lifecycle/timing problems: file log in `Documents/`
   (see spike findings §5).
6. Swift Testing for unit tests; test suite runs at checkpoints (K3, K6, K9, K12) and
   whenever parsers/auth change.
7. Reality contradicts the plan → stop, say so, amend this file in the same commit.

## Architecture

```
Sources/
  App/        entry point, AppEnvironment (owns the services), launch routing
  Auth/       AuthStore (Keychain cookie archive), LoginView, SAPISIDHASH
  Core/       InnerTube client, Models, Parsers   ← copied from kaset, trimmed
  Playback/   WebPlayer (hidden WKWebView + page scripts), PlaybackState, NowPlaying, AudioSession
  Features/   Home, Discover, Collections, Search, Detail, NowPlaying, Queue, Settings
  Debug/      the spike lab (log, heartbeat, raw state), debug builds only
docs/         this plan, tracker, spike findings
Tests/        parsers (fixtures), auth hashing, playback state reducer
```

### Playback model (decided)

- **The web view is the single source of truth.** The page (full `music.youtube.com`
  player, hidden 1×1) owns the queue and advances by itself in the background — the
  spike proved this.
- **The native UI only mirrors.** `WebPlayer` publishes an observable `PlaybackState`
  (track, paused, position, duration, queue snapshot, can-next/prev) built from page
  events + polling.
- **Commands go to the page, then the UI reflects the result.** Play, pause, seek, next,
  previous, *play next*, *add to queue*, shuffle/repeat → a JS call in the page (click the
  player-bar control or call the player API); the UI never mutates state optimistically
  beyond a pending spinner. The state change that comes back updates the screens.
- Starting playback = load `watch?v=ID&list=…` (song + radio/playlist) so the page owns
  a real queue. Lock-screen next/previous use the page's Media Session handlers.
- Native `MPNowPlayingInfoCenter` is published from the mirrored state (title, artist,
  artwork from the API, elapsed/duration), unless a measured comparison (K4) shows the
  page's own card is better.

### Auth contract (decided)

There is no OAuth token: YouTube Music authenticates with Google cookies and signs each
request with `SAPISIDHASH`.

- Sign in in a `WKWebView` with the Mobile Safari UA (suffix
  `Version/17.0 Mobile/15E148 Safari/604.1`), passkey API suppressed (kaset ADR-0033).
- On success `AuthStore` extracts the Google/YouTube auth cookies and archives them in the
  **Keychain** (`AfterFirstUnlock`, this device only).
- At launch the archive is restored into `WKWebsiteDataStore.default()`; the InnerTube
  client reads `SAPISID` from the same jar and computes
  `SAPISIDHASH = SHA1(ts + " " + SAPISID + " " + origin)` per request.
- Account switching: `X-Goog-AuthUser` / brand id as in kaset's `YTMusicClient`.
- Sign out wipes Keychain archive, data store and API caches. Expired session → typed
  error (`authExpired` on 401/403) → sign-in screen.

## UI (decided earlier, unchanged)

Reference: Apple Music on iOS 26. Minimum iOS **26.0**, iPhone first.

- `TabView` with **Home · Discover · Collections · Search** (`Tab(role: .search)` detaches
  to the trailing circle). Every tab has its own `NavigationStack`.
- **Discover** hosts a segmented control: Explore · Charts · Moods · New releases.
- **Collections** hosts a segmented control: Library · Liked music · History.
- Mini player: `.tabViewBottomAccessory`, switching between the full pill and the compact
  inline pill via `tabViewBottomAccessoryPlacement`; `.tabBarMinimizeBehavior(.onScrollDown)`;
  tap → Now Playing with `matchedTransitionSource` + `.navigationTransition(.zoom)`.
- Liquid Glass system materials only. Podcasts, video mode, AI, scrobbling: out of v1.

## Steps

### K0 — Plan, decisions ✅
Spike validated; direction changed to a native app on top of the spike; this plan.

### K1 — Foundations
- Project: rename to `KasetiOS` (bundle `dev.emoona.kaset`, display name Kaset), iOS 26,
  Swift 6 language mode, folder layout above, `.gitignore` for the generated project.
- Move the spike screens/log/script to `Debug/`; the app boots into a minimal root view.
- `AppEnvironment` skeleton and a test target that runs (`xcodebuild test`).
- **Verify (user):** app installs and boots on the iPhone; the debug lab is reachable and
  still plays in the background as before.

### K2 — Auth
- `AuthStore` (Keychain archive, restore, wipe), `LoginView` (mobile UA, passkey
  suppression), cookie-change detection → login complete, `SAPISIDHASH` + unit tests.
- Debug row: signed-in state, account name placeholder (no secrets displayed).
- **Verify (user):** sign in (Premium and, if possible, free), kill + relaunch → still
  signed in, sign out → signed out; nothing sensitive in the log.

### K3 — Core API
- Copy and trim from kaset: `YTMusicClient` (InnerTube request building, headers,
  `authExpired`), `Models/*`, `Parsers/*` for Home, Search (+ suggestions), Browse.
  Use kaset's `api-explorer` and fixtures to validate; never write a parser from inference.
- Debug screen listing Home sections and Search results from the live API.
- **Checkpoint:** unit tests for parsers against sanitized fixtures.
- **Verify (user):** real Home sections and a search appear on device.

### K4 — Playback engine
- `WebPlayer`: hidden 1×1 web view, page scripts (spike script + keep-alive with
  `statechange`/`visibilitychange` resume + Media Session next/previous), command API,
  observable `PlaybackState`, `AudioSession` (interruptions, routes).
- Native Now Playing from the mirrored state (title/artist/artwork/elapsed); measured
  comparison with the page's own card, recorded here.
- Debug transport: play a song id, next/previous/play-next, state readout.
- **Verify (user), spike matrix with real code:** lock 5 min and tracks advance · pause on
  lock screen + 3 min + play · lock-screen next/previous · pause then lock immediately +
  3 min + play · lock-screen shows title, artist, artwork, elapsed.

### K5 — App shell
- Tabs, mini player accessory (mirrors `PlaybackState`), Now Playing presentation stub,
  launch routing (signed out → login, signed in → tabs), minimal Settings.
- **Verify (user):** tabs, mini player persists across tabs and survives backgrounding.

### K6 — Home and Search
- Home shelves (same sections as macOS), pull to refresh, load more; Search with
  suggestions and result sections; tap → play via K4; context menu: play next, add to queue.
- **Checkpoint.**
- **Verify (user):** scroll Home, search, play from results, play next / add to queue
  (queue reflects the page's actual queue).

### K7 — Discover
- Segmented Explore · Charts · Moods · New releases, each keeping scroll and state.
- **Verify (user):** every segment loads, plays, pull to refresh.

### K8 — Collections and detail screens
- Library · Liked music · History; playlist / album / artist detail pushed from anywhere
  (play, shuffle, like, share, add to library). Signed-out state.
- **Verify (user):** like a song and see it in Liked music; history updates.

### K9 — Now Playing and Queue
- Full Now Playing (artwork, scrubber with seek, transport, like, repeat/shuffle, lyrics
  entry, AirPlay, queue sheet with reorder/remove). All controls dispatch to the page; the
  screen reflects the resulting state.
- **Checkpoint.**
- **Verify (user):** every control; seek paused/playing; queue edits honoured on advance.

### K10 — Settings, account, polish
- Audio quality, content language, haptics, account switcher, sign out, diagnostics;
  localization, Dynamic Type, VoiceOver, dark mode.
- **Verify (user):** two languages; VoiceOver on the player; large text.

### K11 — Hardening
- ≥ 60 min locked run with battery delta, WebContent termination recovery (restore
  track/position/queue), expired stream, offline/network change, cold start restore.

### K12 — Docs, distribution
- README (build, sideload, free-account signing limits), CI simulator build.
- **Checkpoint.**

## Backlog

Podcasts · ads handling (opt-in skip would go against YouTube's terms; off if ever added) ·
iPad layout · video mode · synced lyrics · scrobbling · Widgets/Live Activities ·
App Intents · CarPlay (needs an entitlement unavailable to sideloaded builds).
