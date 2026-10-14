import Foundation

// Trimmed from kaset Services/API/YTMusicClient.swift: mood categories, library, liked songs,
// playlist/album detail, artist detail, lyrics, song metadata, ratings.

extension YTMusicClient {
    // MARK: - Mood / genre category

    func getMoodCategory(browseId: String, params: String?) async throws -> HomeResponse {
        var body: [String: Any] = ["browseId": browseId]
        if let params { body["params"] = params }
        let data = try await self.request("browse", body: body, ttl: APICache.TTL.home)
        return HomeResponseParser.parse(data)
    }

    // MARK: - Library

    /// Playlists, saved albums and followed artists. Dedicated endpoints are preferred, the
    /// landing preview is the fallback (kaset keeps the same order of preference).
    func getLibraryContent() async throws -> PlaylistParser.LibraryContent {
        let landingData = try await self.request(
            "browse", body: ["browseId": "FEmusic_library_landing"], ttl: APICache.TTL.library
        )
        let landing = PlaylistParser.parseLibraryContent(landingData)

        var playlists = landing.playlists
        if let data = try? await self.request(
            "browse", body: ["browseId": "FEmusic_liked_playlists"], ttl: APICache.TTL.library
        ) {
            let dedicated = PlaylistParser.parseLibraryPlaylists(data)
            if !dedicated.isEmpty {
                playlists = PlaylistParser.mergedLibraryPlaylists(dedicated: dedicated, fallback: landing.playlists)
            }
        }

        var albums = landing.albums
        if let data = try? await self.request(
            "browse", body: ["browseId": "FEmusic_liked_albums"], ttl: APICache.TTL.library
        ) {
            let page = PlaylistParser.parseLibraryAlbumsPage(data)
            if page.isRecognized || !page.albums.isEmpty {
                albums = PlaylistParser.mergedLibraryAlbums(dedicated: page.albums, fallback: albums)
            }
        }

        var artists = landing.artists
        if let data = try? await self.request(
            "browse",
            body: ["browseId": "FEmusic_library_corpus_artists", "params": "ggMCCAU="],
            ttl: APICache.TTL.library
        ) {
            let dedicated = PlaylistParser.parseLibraryArtists(data)
            if !dedicated.isEmpty { artists = dedicated }
        }

        return PlaylistParser.LibraryContent(
            playlists: playlists, albums: albums, artists: artists,
            podcastShows: [], uploadedSongsPlaylist: nil
        )
    }

    // MARK: - Liked songs

    /// First page of Liked Music (`VLLM` returns the whole list with proper pagination).
    func getLikedSongs() async throws -> LikedSongsResponse {
        let data = try await self.request(
            "browse", body: ["browseId": LikedMusicPlaylist.browseID], ttl: APICache.TTL.library
        )
        let response = PlaylistParser.parsePlaylistWithContinuation(data, playlistId: LikedMusicPlaylist.id)
        return LikedSongsResponse(songs: response.detail.tracks, continuationToken: response.continuationToken)
    }

    func getLikedSongsContinuation(token: String) async throws -> LikedSongsResponse {
        let data = try await self.request(
            "browse", body: ["continuation": token], ttl: APICache.TTL.library, authPolicy: .required
        )
        let response = PlaylistParser.parsePlaylistContinuation(data)
        return LikedSongsResponse(songs: response.tracks, continuationToken: response.continuationToken)
    }

    // MARK: - History

    /// Listening history; never cached, it changes with every song.
    func getHistory() async throws -> HomeResponse {
        try await self.page(.history)
    }

    // MARK: - Playlist / album

    /// Browse id for a playlist, album or radio id (kaset `playlistBrowseId`).
    nonisolated static func playlistBrowseId(for id: String) -> String {
        let loadsAsIs = id.hasPrefix("VL") || id.hasPrefix("RD") || id.hasPrefix("MPRE") || id.hasPrefix("UC")
        return loadsAsIs ? id : "VL\(id)"
    }

    func getPlaylist(id: String) async throws -> PlaylistTracksResponse {
        let data = try await self.request(
            "browse", body: ["browseId": Self.playlistBrowseId(for: id)], ttl: APICache.TTL.playlist
        )
        return PlaylistParser.parsePlaylistWithContinuation(data, playlistId: id)
    }

    func getPlaylistContinuation(token: String, requiresAuth: Bool = false) async throws -> PlaylistContinuationResponse {
        let data = try await self.request(
            "browse", body: ["continuation": token], ttl: APICache.TTL.home,
            authPolicy: requiresAuth ? .required : nil
        )
        return PlaylistParser.parsePlaylistContinuation(data)
    }

    // MARK: - Artist

    func getArtist(id: String) async throws -> ArtistDetail {
        let data = try await self.request("browse", body: ["browseId": id], ttl: APICache.TTL.artist)
        return ArtistParser.parseArtistDetail(data, artistId: id)
    }

    /// Every song of an artist (the page behind "See all" on the top songs shelf).
    func getArtistSongs(browseId: String, params: String?) async throws -> [Song] {
        var body: [String: Any] = ["browseId": browseId]
        if let params { body["params"] = params }
        let data = try await self.request("browse", body: body, ttl: APICache.TTL.artist)
        return ArtistParser.parseArtistSongs(data)
    }

    // MARK: - Song metadata, lyrics, rating

    func getSong(videoId: String) async throws -> Song {
        let body: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]
        let data = try await self.request("next", body: body, ttl: APICache.TTL.songMetadata)
        return try SongMetadataParser.parse(data, videoId: videoId)
    }

    func getLyrics(videoId: String) async throws -> Lyrics {
        let nextBody: [String: Any] = [
            "videoId": videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]
        let nextData = try await self.request("next", body: nextBody)
        guard let browseId = LyricsParser.extractLyricsBrowseId(from: nextData) else { return .unavailable }
        let data = try await self.request("browse", body: ["browseId": browseId], ttl: APICache.TTL.lyrics)
        return LyricsParser.parse(from: data)
    }

    /// like / dislike / remove rating.
    func rateSong(videoId: String, rating: LikeStatus) async throws {
        let endpoint = switch rating {
        case .like: "like/like"
        case .dislike: "like/dislike"
        case .indifferent: "like/removelike"
        }
        _ = try await self.request(endpoint, body: ["target": ["videoId": videoId]])
        self.cache.invalidateMutationCaches()
    }

    // MARK: - Library membership, follow

    func addPlaylistToLibrary(id: String) async throws {
        let clean = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        _ = try await self.request("like/like", body: ["target": ["playlistId": clean]])
        self.cache.invalidate(matching: "browse:")
    }

    func removePlaylistFromLibrary(id: String) async throws {
        let clean = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        _ = try await self.request("like/removelike", body: ["target": ["playlistId": clean]])
        self.cache.invalidate(matching: "browse:")
    }

    func subscribeToArtist(channelId: String) async throws {
        _ = try await self.request("subscription/subscribe", body: ["channelIds": [channelId]])
        self.cache.invalidate(matching: "browse:")
    }

    func unsubscribeFromArtist(channelId: String) async throws {
        _ = try await self.request("subscription/unsubscribe", body: ["channelIds": [channelId]])
        self.cache.invalidate(matching: "browse:")
    }

    // MARK: - Accounts

    func fetchAccountsList() async throws -> AccountsListResponse {
        let data = try await self.request("account/accounts_list", body: [:], authPolicy: .required)
        return AccountsListParser.parse(data)
    }

    // MARK: - Playlists the user owns

    /// The user's playlists as offered by "Add to playlist" for one song.
    func getAddToPlaylistOptions(videoId: String) async throws -> AddToPlaylistMenu {
        let data = try await self.request(
            "playlist/get_add_to_playlist", body: ["videoIds": [videoId]], ttl: nil, authPolicy: .required
        )
        return PlaylistParser.parseAddToPlaylistMenu(data)
    }

    /// Creates a playlist, optionally seeded with songs. Returns the new playlist id.
    func createPlaylist(
        title: String,
        description: String? = nil,
        privacyStatus: PlaylistPrivacyStatus = .private,
        videoIds: [String] = []
    ) async throws -> String {
        var body: [String: Any] = ["title": title, "privacyStatus": privacyStatus.rawValue]
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["description"] = description
        }
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        let data = try await self.request("playlist/create", body: body, authPolicy: .required)
        guard let id = PlaylistParser.parseCreatedPlaylistId(data) else {
            throw YTMusicError.parseError(message: "Missing playlist ID in create playlist response")
        }
        self.cache.invalidateMutationCaches()
        return id
    }

    func addSongToPlaylist(videoId: String, playlistId: String) async throws {
        let clean = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        let body: [String: Any] = [
            "playlistId": clean,
            "actions": [["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId]],
        ]
        _ = try await self.request("browse/edit_playlist", body: body, authPolicy: .required)
        self.cache.invalidateMutationCaches()
    }

    /// `setVideoId` identifies the occurrence (a song can be in a playlist more than once).
    func removeSongFromPlaylist(videoId: String, setVideoId: String, playlistId: String) async throws {
        let clean = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        let body: [String: Any] = [
            "playlistId": clean,
            "actions": [["action": "ACTION_REMOVE_VIDEO", "removedVideoId": videoId, "setVideoId": setVideoId]],
        ]
        _ = try await self.request("browse/edit_playlist", body: body, authPolicy: .required)
        self.cache.invalidateMutationCaches()
    }

    /// Renames a playlist the user owns (`ACTION_SET_PLAYLIST_NAME`, as ytmusicapi does).
    func renamePlaylist(id: String, title: String) async throws {
        let clean = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        let body: [String: Any] = [
            "playlistId": clean,
            "actions": [["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title]],
        ]
        _ = try await self.request("browse/edit_playlist", body: body, authPolicy: .required)
        self.cache.invalidateMutationCaches()
    }

    /// Permanently deletes a playlist the user owns (kaset `deletePlaylist`).
    func deletePlaylist(id: String) async throws {
        let clean = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        _ = try await self.request("playlist/delete", body: ["playlistId": clean], authPolicy: .required)
        self.cache.invalidateMutationCaches()
    }
}
