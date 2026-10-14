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
