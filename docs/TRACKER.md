# Kaset iOS — tracker

Plan: [`PLAN.md`](PLAN.md) · Playback evidence: [`spike-findings.md`](spike-findings.md) ·
Reference app: `~/Desktop/Developer/kaset` (see *Reference* in the plan)

## Protocol — when the user says "continue selon le plan"

1. Read this file; find the **first step not ✅**.
2. **🟦 awaiting verification** → start nothing new; recall what was delivered and its
   checklist (from `PLAN.md`), ask the user to confirm or report problems; fix inside the step.
3. **⬜ todo / 🟨 in progress** → implement only that step: set 🟨, keep the build green,
   run tests when the plan says checkpoint (or parsers/auth changed), commit with the step
   id (`feat: K4 playback engine`), set 🟦 with the commit hash, add a Log line, present the
   summary + checklist, then **stop**.
4. ✅ only when the user explicitly confirms (record the date).
5. Never skip ahead, never merge two steps. If the user explicitly asks to chain steps,
   still commit per step and mark each 🟦.
6. Before implementing a step, read the matching rows of the plan's *Reference* table in
   kaset; do not write API code from inference.
7. If reality contradicts the plan, stop and amend `PLAN.md` in the same commit.

## Decisions

| ID | Decision | Status |
|---|---|---|
| D1 | Minimum iOS 26.0, iPhone first | ✅ 2026-10-14 |
| D2 | XcodeGen project | ✅ |
| D3 | Bundle id `dev.emoona.kaset`, name "Kaset" | ✅ |
| D4 | v1: YouTube Music only (no video, AI, extensions, EQ, scrobbling, podcasts) | ✅ |
| D5 | Native app on top of the spike (this repo); kaset macOS = reference, sources copied | ✅ 2026-10-14 |
| D6 | The web view is the source of truth; native UI mirrors it; commands go to the page | ✅ 2026-10-14 |
| D7 | Auth = cookies archived in Keychain + SAPISIDHASH signing, in a standalone `AuthStore` | ✅ 2026-10-14 |

## Steps

| ID | Step | Status | Commit | Confirmed |
|---|---|---|---|---|
| K0 | Plan, decisions | ✅ | (this commit) | 2026-10-14 |
| K1 | Foundations | ✅ | 70f5a43 | 2026-10-14 |
| K2 | Auth | ✅ | aa7d884 | 2026-10-14 |
| K3 | Core API | ✅ | e3e5f3b | 2026-10-14 |
| K4 | Playback engine | ✅ | 087f867 | 2026-10-14 |
| K5 | App shell | ✅ | e00721f | 2026-10-14 |
| K6 | Home and Search | ✅ | 19cbf63 | 2026-10-14 |
| K7 | Discover | ⬜ | | |
| K8 | Collections and detail screens | ⬜ | | |
| K9 | Now Playing and Queue | ⬜ | | |
| K10 | Settings, account, polish | ⬜ | | |
| K11 | Hardening | ⬜ | | |
| K12 | Docs, distribution | ⬜ | | |

## Findings carried over from the abandoned port (kaset `feat/ios-port`, S1–S5)

- The spike's web view (full YTM page, `preferredContentMode = .desktop`, desktop UA for
  playback, Mobile Safari suffix for sign-in) played and showed lock-screen metadata; the
  port's `watch?v=` + stripped page did not show metadata → keep the spike's page model.
- `allowsInlineMediaPlayback = true` and `allowsPictureInPictureMediaPlayback = false` are
  required, otherwise iOS promotes the video to full screen / PiP.
- `MPNowPlayingInfoCenter.playbackState` is ignored on iOS without an entitlement
  (`[MRNowPlaying] Ignoring setPlaybackState`); rely on the page / info dictionary.
- Port-era files worth copying later: kaset `Sources/KasetiOS/Playback/IOSPlaybackScripts.swift`
  (keep-alive + next/previous flag), `AudioSessionController.swift`.

## Log

| Date | Step | Note |
|---|---|---|
| 2026-10-14 | K0 | Direction changed: the spike becomes the app (`Kaset-iOS`, renamed from `YoutubeMusic Spik`). Plan and tracker moved here and re-planned (K1–K12) with the already-decided UI. kaset `feat/ios-port` frozen as reference (S1 ✅, S2 ✅, S3–S5 🟦 never confirmed). |
| 2026-10-14 | K1 | Project renamed `KasetiOS` (bundle `dev.emoona.kaset`, iOS 26, Swift 6 builds clean), `App/` + `Debug/` layout, `AppEnvironment` owns the lab player (hidden 1×1 host while the lab is closed), test target green on iPhone 17 simulator (iOS 26.2). Awaiting device verification. |
| 2026-10-14 | K2 | `Auth/`: `AuthCookies` (allowlist, SAPISID selection, `SAPISIDHASH`, plist archive), `CookieVault` (Keychain AfterFirstUnlockThisDeviceOnly), `AuthStore` (restore at launch, debounced re-archive on cookie change, sign-out wipes vault + jar + website data), `LoginView`. Kaset's restore-policy/transaction machinery deliberately not copied (single blob). Root view has a sign in/out row. 11 tests green. Awaiting device verification (K1 + K2). |
| 2026-10-14 | K3 | `Core/`: models + Home/Search/Suggestions parsers copied from kaset (type names kept), `YTMusicClient` trimmed to browse pages (+continuations), search (+continuation), suggestions; auth via `AuthStore` (SAPISIDHASH, 401/403 → `authExpired` + `sessionExpired()`); API key resolved from the page. Checkpoint: kaset's Home/Search/Suggestions/ParsingHelpers/ResponseTreeSearch tests + fixtures ported, 119 tests green. `Debug/APIDebugView` shows live Home + Search. Not run against the live API yet (needs the device session). |
| 2026-10-14 | K1–K3 | Confirmed on device by the user. Next: K4 (playback engine). |
| 2026-10-14 | K4 | `Playback/`: `WebPlayer` (hidden 1×1 desktop-mode web view, commands go to the page, `PlaybackState` mirrors page events + 2 s/5 s heartbeat incl. queue snapshot), `PlayerScripts` (spike keep-alive + statechange/visibilitychange resume, Media Session next/previous, kaset play-next injection), `NowPlayingPublisher` (toggle `nativeNowPlaying`, default on), audio session + interruptions, diagnostics log. Spike lab retired. JS syntax checked with node; reducer tests green (126). **Not measured on device**: native vs page Now Playing card comparison and the 5-point background matrix are the user's verification. |
| 2026-10-14 | K5 | `Features/Shell`: `MainTabView` (Home/Discover/Collections/Search role, `tabBarMinimizeBehavior(.onScrollDown)`, `tabViewBottomAccessory` mini player with inline/expanded placement, zoom transition to the Now Playing stub), `SignInView`, launch routing in `RootView`, minimal `SettingsView` (account + diagnostics entry). Tabs hold placeholders until K6–K8. Builds + tests green; not run on device. |
| 2026-10-14 | K6 | `Features/Home` (shelves, pull to refresh, load more via continuation), `Features/Search` (suggestions, grouped results), shared `MediaEntity`/`MediaActions`: tap = `WebPlayer.play` (songs → radio `RDAMVM<id>`, playlists → `watch?list=`), context menu = play / play next / add to queue (new `PlayerScripts.addToQueue`, inspired by kaset's queue injection, **unverified on a real page**). Albums/artists push a placeholder until K8. Tests 129 green. Awaiting device verification. |
| 2026-10-14 | K4–K6 | Confirmed on device by the user after the Now Playing artwork isolation fix. |
