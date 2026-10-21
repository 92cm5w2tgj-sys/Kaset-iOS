import Foundation

// Ported from kaset: Services/Lyrics/Providers/LRCLibProvider.swift. YouTube Music rarely
// returns timed lyrics to the web client; LRCLib (a free, open lyrics database) fills the gap.

/// Searches lrclib.net for a track; prefers the entry whose length is closest to the track's.
enum LRCLibClient {
    private struct Entry: Decodable {
        let duration: TimeInterval?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    static let sourceName = "LRCLib"

    static func search(title: String, artist: String, duration: TimeInterval?) async -> LyricResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components.url else { return .unavailable }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Kaset-iOS (https://github.com/emoonadev)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return .unavailable }

        let candidates = entries.filter {
            ($0.syncedLyrics != nil || $0.plainLyrics != nil) && $0.instrumental != true
        }
        let best = if let duration, duration > 0 {
            candidates.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
        } else {
            candidates.first
        }
        guard let best else { return .unavailable }
        // A match more than 10 s off is most likely another version (live, remix, edit).
        if let duration, duration > 0, let found = best.duration, abs(found - duration) > 10 {
            return .unavailable
        }

        if let synced = best.syncedLyrics, let parsed = LRCParser.parse(synced) {
            return .synced(SyncedLyrics(lines: parsed.lines, source: self.sourceName))
        }
        if let plain = best.plainLyrics, !plain.isEmpty {
            return .plain(Lyrics(text: plain, source: "Source: \(self.sourceName)"))
        }
        return .unavailable
    }
}
