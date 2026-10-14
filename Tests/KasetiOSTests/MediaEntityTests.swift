import Foundation
import Testing

@testable import KasetiOS

struct MediaEntityTests {
    @Test func stripsBrowsePrefixFromPlaylistIds() {
        #expect(MediaEntity.watchPlaylistId("VLPLabc") == "PLabc")
        #expect(MediaEntity.watchPlaylistId("RDCLAK5uy_x") == "RDCLAK5uy_x")
    }

    @Test func searchSongMapsToPlayableSong() throws {
        let data: [String: Any] = try JSONSerialization.jsonObject(
            with: Data(contentsOf: #require(Bundle(for: FixtureBundleToken.self).url(forResource: "search_response", withExtension: "json")))
        ) as? [String: Any] ?? [:]
        let response = SearchResponseParser.parse(data)
        let song = try #require(response.songs.first)
        let entity = MediaEntity(SearchResultItem.song(song))
        #expect(entity.videoId == song.videoId)
        #expect(entity.title == song.title)
        #expect(!entity.isCircular)
    }

    @Test func artistsAreCircularAndNavigable() {
        let artist = Artist(id: "UC123", name: "Someone")
        let entity = MediaEntity(HomeSectionItem.artist(artist))
        #expect(entity.isCircular)
        #expect(entity.target == .artist(id: "UC123"))
    }
}

struct NowPlayingIndicatorTests {
    private func entity(_ target: MediaEntity.Target, title: String = "T") -> MediaEntity {
        MediaEntity(id: "x", title: title, subtitle: nil, thumbnailURL: nil, target: target, isCircular: false)
    }

    @Test func songMatchesByVideoId() {
        let identity = PlaybackIdentity(videoId: "abc", listId: nil, album: nil, isPlaying: true)
        #expect(self.entity(.song(videoId: "abc")).isCurrent(in: identity))
        #expect(!self.entity(.song(videoId: "zzz")).isCurrent(in: identity))
    }

    @Test func playlistMatchesByListWithoutBrowsePrefix() {
        let identity = PlaybackIdentity(videoId: "abc", listId: "PLxyz", album: nil, isPlaying: false)
        #expect(self.entity(.playlist(id: "VLPLxyz")).isCurrent(in: identity))
        #expect(!self.entity(.playlist(id: "VLPLother")).isCurrent(in: identity))
    }

    @Test func albumMatchesByNameIgnoringCase() {
        let identity = PlaybackIdentity(videoId: "abc", listId: nil, album: "Some Album", isPlaying: true)
        #expect(self.entity(.album(id: "MPREb_1"), title: "some album").isCurrent(in: identity))
        #expect(!self.entity(.album(id: "MPREb_1"), title: "Other").isCurrent(in: identity))
    }

    @Test func nothingMatchesWhenNothingPlays() {
        let identity = PlaybackIdentity()
        #expect(!self.entity(.song(videoId: "abc")).isCurrent(in: identity))
        #expect(!self.entity(.album(id: "MPREb_1")).isCurrent(in: identity))
    }

    @Test func searchFiltersCarryTheirParams() {
        #expect(SearchFilter.all.params == nil)
        #expect(SearchFilter.songs.params == "EgWKAQIIAWoMEA4QChADEAQQCRAF")
        #expect(Set(SearchFilter.allCases.compactMap(\.params)).count == 5)
    }
}
