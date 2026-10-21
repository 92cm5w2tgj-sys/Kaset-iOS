import Testing

@testable import KasetiOS

struct ShelfMoreEndpointTests {
    private static func carousel(browseId: String, params: String? = nil, pageType: String? = nil) -> [String: Any] {
        var endpoint: [String: Any] = ["browseId": browseId]
        if let params { endpoint["params"] = params }
        if let pageType {
            endpoint["browseEndpointContextSupportedConfigs"] = [
                "browseEndpointContextMusicConfig": ["pageType": pageType],
            ]
        }
        return [
            "header": [
                "musicCarouselShelfBasicHeaderRenderer": [
                    "moreContentButton": [
                        "buttonRenderer": ["navigationEndpoint": ["browseEndpoint": endpoint]],
                    ],
                ],
            ],
        ]
    }

    @Test(.tags(.parser)) func readsTheMoreButtonOfACarousel() throws {
        let data = Self.carousel(browseId: "MPAD123", params: "abc", pageType: "MUSIC_PAGE_TYPE_ARTIST_DISCOGRAPHY")
        let endpoint = try #require(ShelfMoreEndpoint.fromCarousel(data))
        #expect(endpoint == ShelfMoreEndpoint(browseId: "MPAD123", params: "abc", pageType: .discography))
    }

    @Test(.tags(.parser)) func keepsEndpointsWithoutAKnownPageType() throws {
        let endpoint = try #require(ShelfMoreEndpoint.fromCarousel(Self.carousel(browseId: "FEmusic_listen_again")))
        #expect(endpoint.pageType == nil)
        #expect(endpoint.params == nil)
    }

    @Test(.tags(.parser)) func shelvesWithoutAMoreButtonHaveNone() {
        #expect(ShelfMoreEndpoint.fromCarousel(["header": ["musicCarouselShelfBasicHeaderRenderer": [:]]]) == nil)
        #expect(ShelfMoreEndpoint.fromCarousel([:]) == nil)
    }
}
