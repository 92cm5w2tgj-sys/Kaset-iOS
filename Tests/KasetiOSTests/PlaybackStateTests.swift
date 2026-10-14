import Foundation
import Testing

@testable import KasetiOS

struct PlaybackStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func appliesPlayingMessage() {
        let state = PlaybackState().applying([
            "kind": "state", "paused": false, "ended": false, "currentTime": 12.5, "duration": 200.0,
            "videoId": "abc", "title": "Song", "artist": "Artist", "artwork": "https://example.com/a.jpg",
            "canNext": true, "canPrevious": false, "vis": "hidden",
        ], at: self.t0)
        #expect(state.isPlaying)
        #expect(state.hasMedia)
        #expect(state.position == 12.5)
        #expect(state.duration == 200)
        #expect(state.videoId == "abc")
        #expect(state.artworkURL?.absoluteString == "https://example.com/a.jpg")
        #expect(state.canGoNext && !state.canGoPrevious)
        #expect(state.visibility == "hidden")
    }

    @Test func pausedAndEndedAreNotPlaying() {
        let paused = PlaybackState().applying(["paused": true, "ended": false])
        #expect(!paused.isPlaying && paused.hasMedia)
        let ended = PlaybackState().applying(["paused": false, "ended": true])
        #expect(!ended.isPlaying)
    }

    @Test func nullPausedMeansNoMedia() {
        let playing = PlaybackState().applying(["paused": false, "ended": false])
        let gone = playing.applying(["paused": NSNull()])
        #expect(!gone.hasMedia && !gone.isPlaying)
    }

    @Test func absentKeysKeepPreviousValues() {
        let first = PlaybackState().applying(["paused": false, "title": "A", "queue": [["videoId": "x", "title": "X", "artist": "Y", "current": true]]])
        let second = first.applying(["paused": false, "currentTime": 3.0])
        #expect(second.title == "A")
        #expect(second.queue.count == 1)
        #expect(second.queue[0].isCurrent)
    }

    @Test func nullTitleClearsIt() {
        let first = PlaybackState().applying(["title": "A"])
        #expect(first.applying(["title": NSNull()]).title == nil)
    }

    @Test func positionExtrapolatesOnlyWhilePlaying() {
        var state = PlaybackState().applying(["paused": false, "ended": false, "currentTime": 10.0, "duration": 100.0], at: self.t0)
        #expect(state.position(at: self.t0.addingTimeInterval(5)) == 15)
        #expect(state.position(at: self.t0.addingTimeInterval(500)) == 100)
        state = state.applying(["paused": true, "ended": false, "currentTime": 20.0], at: self.t0)
        #expect(state.position(at: self.t0.addingTimeInterval(30)) == 20)
    }

    @Test func scriptLiteralEscapes() {
        #expect(PlayerScripts.literal("a\"b") == "\"a\\\"b\"")
    }
}
