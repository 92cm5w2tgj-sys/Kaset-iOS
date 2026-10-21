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
- [x] Synced lyrics: highlighted line follows playback, tap a line to seek (YouTube Music, LRCLib
      fallback)
- [x] Player health screen (*Settings → Diagnostics*): shows which page parts still respond,
      probed after every track change; new failures are logged
- [x] "See all" on Home, mood and artist shelves
- [x] "Start radio" from the menu of a song (shelves, track rows, Now Playing)
- [x] History grouped by period (Today, Yesterday, This week…) as a track list
- [x] Bad network: no reload while offline (resume when the network is back), low quality after
      an underrun or in Low Data Mode, buffer-ahead readout in the log and health screen
- [x] Play without a page load when YouTube Music's router is gone (`yt-navigate` fallback)
- [x] Play after a media error (device locked while paused) reloads the track at its position

## Robustness (do first)

- [ ] **Verify on device** (code shipped, not yet measured):
  - Longer buffer (*Settings → Bad network*, relaunch): do the `[buffer] … ahead=` log lines
    go well past ~25-35 s? If not, YouTube's `enable_server_driven_readahead` probably caps it
  - `yt-navigate` fallback: a play from the app logs `yt-navigate watch …` with no page load
    after it; send the `[router] ytmusic-app: …` line
  - Locking while paused, then play: the track comes back at its position
- [ ] **Direct queue reorder**: the page's queue object has no move method (`removeItem`,
      `shuffle`, `selectQueueItem` and an internal `store.dispatch` only); would need the
      internal action name, so on hold
- [ ] **Measured soak tests**: 60 min locked run with battery delta; phone call, AirPods
      disconnect and network handover recovery

## Music features

- [ ] **Listening recap**: week / month / year — minutes, top artists, top tracks, hours of
      the day, new artists; shareable card. Plays are recorded on the device (a play counts
      after 30 s); starts empty, no backfill. Sync through a file in iCloud Drive that I pick
      once (document picker + bookmark): CloudKit needs a paid developer account
- [ ] **My stats on artist pages**: plays, minutes, favourite track and first listen, from the
      recap data
- [ ] **On this day**: what I was playing a month / a year ago, one tap to play it again
      (recap data; useful after a few months)
- [ ] **New releases from my artists**: recent albums and singles from the artists I follow or
      play most, with optional local notifications (background refresh, no server)
- [ ] **Find a song by its lyrics**: type a line you remember, LRCLib full-text search finds the
      song, YouTube Music search opens it
- [ ] **Music for a set duration**: "45 min" builds a queue that fits the trip or the workout
- [ ] **Recognise the music around me**: a Shortcut *Recognise Music* (Shazam, built into
      Shortcuts) → app intent "Search and play" opens the match in the app (play, like, add to
      playlist). In-app ShazamKit would need a paid developer account
- [ ] ~~Offline / download of liked songs~~ not feasible: playback goes through the web player

## iOS integration

- [ ] **Widgets**: now-playing widget with play/pause (App Group + App Intents)
- [ ] **App Intents / Siri / Shortcuts**: "Play my playlist X", "Start a radio", "Like this
      song"; usable by Siri with Apple Intelligence and by the Shortcuts *Use Model* action
- [ ] **Visual Intelligence** (iOS 26): results from the app when analysing an image (album
      cover, concert poster → artist / album)
- [ ] **CarPlay**: blocked by Apple's `carplay-audio` entitlement (not available to sideloaded
      builds); the system *Now Playing* screen already works
- [ ] **Wake up to music**: an App Intent "Play playlist X" that a Shortcuts personal
      automation runs when the Clock alarm is stopped; optionally an in-app AlarmKit alarm
      (iOS 26) whose button opens the app and starts the playlist
- [ ] **Spotlight**: index my playlists, albums and liked songs (Core Spotlight) so they can be
      found and played from the iPhone search
- [ ] **iPad layout**: sidebar and two-column detail screens

## Apple Intelligence

On-device, free, no server. Needs an Apple Intelligence iPhone (15 Pro or later) with Apple
Intelligence on; the features hide themselves otherwise. Hebrew support of the model to be
checked first (spike on device).

- [ ] **Playlist from a sentence** (Foundation Models): "calm music for night driving, Hebrew
      and French" → the model turns it into YouTube Music searches and picks from liked songs
      (tool calling), then plays it as a queue or saves it as a playlist
- [ ] **Playlist name and description** suggested from the tracks it contains
- [ ] **Generated playlist covers** (Image Playground) from the playlist name or mood

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
- Live Activity: the system Now Playing card already covers the lock screen and Dynamic Island
