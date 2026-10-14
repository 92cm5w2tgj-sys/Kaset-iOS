# Kaset iOS — tracker

Plan: [`PLAN.md`](PLAN.md) · Playback evidence: [`spike-findings.md`](spike-findings.md)

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
6. If reality contradicts the plan, stop and amend `PLAN.md` in the same commit.

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
| K1 | Foundations | ⬜ | | |
| K2 | Auth | ⬜ | | |
| K3 | Core API | ⬜ | | |
| K4 | Playback engine | ⬜ | | |
| K5 | App shell | ⬜ | | |
| K6 | Home and Search | ⬜ | | |
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
