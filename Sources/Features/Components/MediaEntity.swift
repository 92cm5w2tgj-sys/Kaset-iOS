import Foundation

/// A tappable thing in a shelf or a result list, reduced to what the UI needs.
/// The native UI never plays anything itself: `MediaActions` turns taps into web view commands.
struct MediaEntity: Identifiable, Hashable {
    enum Target: Hashable {
        case song(videoId: String)
        case playlist(id: String)
        case album(id: String)
        case artist(id: String)
        case mood(browseId: String, params: String?)
        case unsupported
    }

    let id: String
    let title: String
    let subtitle: String?
    let thumbnailURL: URL?
    let target: Target
    let isCircular: Bool

    var videoId: String? {
        if case let .song(videoId) = self.target { return videoId }
        return nil
    }

    var kindLabel: String {
        switch self.target {
        case .song: "Song"
        case .playlist: "Playlist"
        case .album: "Album"
        case .artist: "Artist"
        case .mood: "Mood"
        case .unsupported: ""
        }
    }
}

extension MediaEntity {
    init(_ song: Song, id: String? = nil) {
        self.init(
            id: id ?? "song-\(song.id)",
            title: song.title,
            subtitle: song.artistsDisplay.isEmpty ? nil : song.artistsDisplay,
            thumbnailURL: song.thumbnailURL,
            target: .song(videoId: song.videoId),
            isCircular: false
        )
    }

    init(_ item: HomeSectionItem) {
        switch item {
        case let .song(song):
            self.init(song, id: item.id)
        case let .album(album):
            self.init(
                id: item.id, title: album.title, subtitle: album.artistsDisplay.isEmpty ? nil : album.artistsDisplay,
                thumbnailURL: album.thumbnailURL, target: .album(id: album.id), isCircular: false
            )
        case let .playlist(playlist):
            if let mood = playlist.resolvedMoodCategoryEndpoint {
                self.init(
                    id: item.id, title: playlist.title, subtitle: nil, thumbnailURL: nil,
                    target: .mood(browseId: mood.browseId, params: mood.params), isCircular: false
                )
            } else {
                self.init(
                    id: item.id, title: playlist.title, subtitle: playlist.author?.name,
                    thumbnailURL: playlist.thumbnailURL, target: .playlist(id: playlist.id), isCircular: false
                )
            }
        case let .artist(artist):
            self.init(
                id: item.id, title: artist.name, subtitle: artist.subtitle,
                thumbnailURL: artist.thumbnailURL, target: .artist(id: artist.id), isCircular: true
            )
        }
    }

    init(_ item: SearchResultItem) {
        switch item {
        case let .song(song), let .video(song):
            self.init(song, id: item.id)
        case let .album(album), let .audiobook(album):
            self.init(
                id: item.id, title: album.title, subtitle: item.subtitle,
                thumbnailURL: album.thumbnailURL, target: .album(id: album.id), isCircular: false
            )
        case let .artist(artist), let .profile(artist):
            self.init(
                id: item.id, title: artist.name, subtitle: item.subtitle,
                thumbnailURL: artist.thumbnailURL, target: .artist(id: artist.id), isCircular: true
            )
        case let .playlist(playlist):
            self.init(
                id: item.id, title: playlist.title, subtitle: item.subtitle,
                thumbnailURL: playlist.thumbnailURL, target: .playlist(id: playlist.id), isCircular: false
            )
        case .podcastShow, .podcastEpisode:
            // Podcasts are out of v1.
            self.init(
                id: item.id, title: item.title, subtitle: item.subtitle,
                thumbnailURL: item.thumbnailURL, target: .unsupported, isCircular: false
            )
        }
    }

    /// Playlist ids from browse carry a `VL` prefix that `watch?list=` does not accept.
    static func watchPlaylistId(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }
}

extension MediaEntity {
    init(_ playlist: Playlist) {
        self.init(
            id: "playlist-\(playlist.id)", title: playlist.title, subtitle: playlist.author?.name,
            thumbnailURL: playlist.thumbnailURL, target: .playlist(id: playlist.id), isCircular: false
        )
    }

    init(_ album: Album) {
        self.init(
            id: "album-\(album.id)", title: album.title,
            subtitle: album.artistsDisplay.isEmpty ? nil : album.artistsDisplay,
            thumbnailURL: album.thumbnailURL, target: .album(id: album.id), isCircular: false
        )
    }

    init(_ artist: Artist) {
        self.init(
            id: "artist-\(artist.id)", title: artist.name, subtitle: artist.subtitle,
            thumbnailURL: artist.thumbnailURL, target: .artist(id: artist.id), isCircular: true
        )
    }
}
