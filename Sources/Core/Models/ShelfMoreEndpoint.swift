import Foundation

// MARK: - ArtistShelfKind

/// Identifies which carousel shelf an artist-page More/See-all endpoint belongs to.
///
/// Shelves are matched by renderer shape + browseId prefix at parse time
/// (see `ArtistParser.classifyCarouselItem`). Each kind corresponds to one
/// bucket on `ArtistDetail` and — when its shelf exposes a `moreContentButton`
/// in the API response — one entry in `ArtistDetail.moreEndpoints`.
enum ArtistShelfKind: Hashable {
    case albums
    case singles
    case videos
    case episodes
    case livePerformances
    case featuredOn
    case playlistsByArtist
    case podcasts
    case relatedArtists
}

// MARK: - ShelfMoreEndpoint

/// A browse endpoint captured from a carousel shelf's `moreContentButton` (the "More" /
/// "See all" link on Home and artist shelves).
///
/// `MUSIC_PAGE_TYPE_PLAYLIST` opens the playlist page; anything else is fetched with
/// `/browse` (`browseId` + `params`) and shown as a grid of the sections it returns.
struct ShelfMoreEndpoint: Hashable {
    /// Page-type tags observed in practice on shelves.
    enum PageType: String, Hashable {
        case playlist = "MUSIC_PAGE_TYPE_PLAYLIST"
        case artist = "MUSIC_PAGE_TYPE_ARTIST"
        case discography = "MUSIC_PAGE_TYPE_ARTIST_DISCOGRAPHY"
    }

    let browseId: String
    let params: String?
    /// `nil` when the endpoint carries no page type, or one not listed above.
    let pageType: PageType?

    /// Reads `header.musicCarouselShelfBasicHeaderRenderer.moreContentButton` of a
    /// `musicCarouselShelfRenderer`.
    static func fromCarousel(_ data: [String: Any]) -> ShelfMoreEndpoint? {
        guard let header = data["header"] as? [String: Any],
              let basicHeader = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let moreButton = basicHeader["moreContentButton"] as? [String: Any],
              let buttonRenderer = moreButton["buttonRenderer"] as? [String: Any]
        else {
            return nil
        }

        let endpointContainer = (buttonRenderer["command"] as? [String: Any])
            ?? (buttonRenderer["navigationEndpoint"] as? [String: Any])

        guard let browseEndpoint = endpointContainer?["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String, !browseId.isEmpty
        else {
            return nil
        }

        let supportedConfigs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any]
        let musicConfig = supportedConfigs?["browseEndpointContextMusicConfig"] as? [String: Any]
        let pageType = (musicConfig?["pageType"] as? String).flatMap(PageType.init(rawValue:))
        return ShelfMoreEndpoint(browseId: browseId, params: browseEndpoint["params"] as? String, pageType: pageType)
    }
}

// MARK: - SeeAllDestination

/// Navigation value behind a shelf's "See all" link.
struct SeeAllDestination: Hashable {
    let title: String
    let endpoint: ShelfMoreEndpoint
}
