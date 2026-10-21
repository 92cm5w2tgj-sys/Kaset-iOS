import Testing

@testable import KasetiOS

struct LyricsTests {
    /// Lines carry a random id, so each value is built once and compared to itself.
    private static func synced(_ source: String) -> LyricResult {
        .synced(SyncedLyrics(lines: [SyncedLyricLine(timeInMs: 0, duration: 1000, text: "la", words: nil)], source: source))
    }

    private static let youtubeSynced = synced("YTMusic")
    private static let lrclibSynced = synced("LRCLib")

    private static let plain = LyricResult.plain(Lyrics(text: "la la", source: "Source: LyricFind"))

    @MainActor @Test func syncedLyricsWinOverPlainWhateverTheSource() {
        #expect(NowPlayingModel.preferred(Self.plain, Self.lrclibSynced) == Self.lrclibSynced)
        #expect(NowPlayingModel.preferred(Self.youtubeSynced, Self.lrclibSynced) == Self.youtubeSynced)
    }

    @MainActor @Test func youTubeMusicWinsATieAndUnavailableFallsThrough() {
        let lrclibPlain = LyricResult.plain(Lyrics(text: "other", source: "Source: LRCLib"))
        #expect(NowPlayingModel.preferred(Self.plain, lrclibPlain) == Self.plain)
        #expect(NowPlayingModel.preferred(.unavailable, lrclibPlain) == lrclibPlain)
        #expect(NowPlayingModel.preferred(.unavailable, .unavailable) == .unavailable)
    }

    @Test func lrcLinesAreTimedAndTheCurrentLineFollowsTheClock() throws {
        let lyrics = try #require(LRCParser.parse("[00:01.00]one\n[00:03.50]two\n[00:06.00]three"))
        // A blank lead-in line is inserted before the first line.
        #expect(lyrics.lines.map(\.text) == ["", "one", "two", "three"])
        #expect(lyrics.currentLineIndex(at: 500) == 0)
        #expect(lyrics.currentLineIndex(at: 1200) == 1)
        #expect(lyrics.currentLineIndex(at: 3500) == 2)
        #expect(lyrics.currentLineIndex(at: 7000) == 3)
    }
}
