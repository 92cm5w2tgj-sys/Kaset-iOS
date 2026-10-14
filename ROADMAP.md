# Roadmap

What is shipped, and what comes next. Items are ordered by value for daily use and by cost;
nothing here is a promise. Contributions are welcome: open an issue before starting anything big.

Legend: `[x]` shipped · `[ ]` planned.

## Shipped

- [x] Native SwiftUI shell: Home, Discover, Collections, Search, mini player accessory
- [x] Background playback, lock-screen / AirPods controls, native Now Playing card
- [x] Hidden web player as the single source of truth; native UI only commands and mirrors
- [x] Sign-in, guest mode, brand-account switching, avatar in the navigation bar
- [x] Home, Explore, Charts, Moods (grid), New, Library, Liked music, History
- [x] Playlist, album and artist pages (iOS-style header, now-playing indicator)
- [x] Search with recent searches, suggestions, kind segments and paginated filtered results
- [x] Now Playing in the Apple Music layout (artwork tint, scrubber, volume, lyrics, AirPlay)
- [x] Queue: jump, remove, reorder, play next, add to queue
- [x] Like, add to library, follow, share
- [x] Create / rename / delete playlists, add songs or whole covers to a playlist
- [x] Recovery after web content termination, network changes and stuck streams; session restore
- [x] Audio quality, content language, haptics, opt-in ad skipping
- [x] English and French

## Robustness (do first)

- [ ] **Direct queue reorder**: call the page's own queue API instead of removing and
      re-inserting entries (needs the `q.queue.*` members from *Settings → Diagnostics →
      Inspect queue*)
- [ ] **Measured soak tests**: 60 min locked run with battery delta; phone call, AirPods
      disconnect and network handover recovery
- [ ] **Player health screen**: show which page selectors still respond (shuffle, repeat,
      queue, add to queue) so a YouTube Music DOM change is visible immediately

## Music features

- [ ] **"See all" on Home and artist sections** (the more-endpoints are already parsed)
- [ ] **Synced lyrics**: highlighted line follows playback, tap a line to seek
      (`LRCParser` and `SyncedLyrics` models are already in the project)
- [ ] **"Start radio"** from the long-press menu of a song
- [ ] **History grouped by day** (Today, Yesterday, This week)
- [ ] ~~Offline / download of liked songs~~ not feasible: playback goes through the web player

## iOS integration

- [ ] **Widgets**: now-playing widget with play/pause (App Group + App Intents)
- [ ] **App Intents / Siri**: "Play my playlist X"
- [ ] **Live Activity / Dynamic Island** for the current track
- [ ] **CarPlay**: blocked by Apple's `carplay-audio` entitlement (not available to sideloaded
      builds); the system *Now Playing* screen already works
- [ ] **iPad layout**: sidebar and two-column detail screens

## Quality

- [ ] **UI tests**: Home → play → Now Playing flow against a fake client
- [ ] **Accessibility pass**: full VoiceOver audit, largest Dynamic Type on detail and Now Playing
- [ ] **More languages**: Spanish, German, Hebrew (RTL layout check)
- [ ] **Distribution**: GitHub release with an unsigned `.ipa` and an AltStore / SideStore guide

## Out of scope for now

- YouTube-wide search and video playback (a separate client and a real video player)
- Podcasts
- Scrobbling (Last.fm, ListenBrainz)
- Equalizer
