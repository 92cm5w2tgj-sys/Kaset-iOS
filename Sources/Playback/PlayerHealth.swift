import Foundation

/// Result of `window.__kaset.health()`: which parts of the YouTube Music page the app drives
/// still respond. A YouTube Music DOM change shows up here as a failing check.
struct PlayerHealthReport: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case ok
        case failing
        /// Only testable while a track is loaded.
        case needsTrack
    }

    struct Check: Equatable, Identifiable, Sendable {
        let id: String
        let ok: Bool
        let detail: String
        let needsTrack: Bool
        let hasTrack: Bool

        var status: Status {
            if self.ok { return .ok }
            return self.needsTrack && !self.hasTrack ? .needsTrack : .failing
        }

        var title: String { Self.descriptions[self.id]?.title ?? self.id }
        /// What stops working when this check fails.
        var usedBy: String { Self.descriptions[self.id]?.usedBy ?? "" }

        private static let descriptions: [String: (title: String, usedBy: String)] = [
            "page": ("Page script", "Everything: the app cannot talk to the page"),
            "media": ("Media element", "Playback state, position, play / pause"),
            "playerApi": ("Player API", "Seeking, track id, next / previous fallback"),
            "router": ("Router", "Starting a song, album or playlist"),
            "mediaSession": ("Media Session metadata", "Title, artist and artwork"),
            "playerBar": ("Player bar", "Transport buttons, shuffle, repeat, menu"),
            "playPause": ("Play / pause button", "Play / pause from the app and lock screen"),
            "next": ("Next button", "Next track"),
            "previous": ("Previous button", "Previous track"),
            "shuffle": ("Shuffle button", "Shuffle toggle and its state"),
            "repeat": ("Repeat button", "Repeat toggle and its state"),
            "menu": ("Player bar menu", "Play next, add to queue"),
            "queue": ("Queue list", "Queue screen, jump, remove, reorder"),
            "queueIds": ("Queue video ids", "Play next / add to queue checks, reorder"),
            "queueCurrent": ("Current queue entry", "Now-playing marker in the queue, play next"),
        ]
    }

    let checks: [Check]
    let hasTrack: Bool
    let date: Date

    var failing: [Check] { self.checks.filter { $0.status == .failing } }

    /// Report for a page that did not answer at all.
    static func unreachable(_ detail: String, at date: Date = Date()) -> PlayerHealthReport {
        PlayerHealthReport(
            checks: [Check(id: "page", ok: false, detail: detail, needsTrack: false, hasTrack: false)],
            hasTrack: false, date: date
        )
    }

    /// Parses the JSON text of `health()`; `nil` when it is not a health result.
    static func parse(_ json: String, at date: Date = Date()) -> PlayerHealthReport? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawChecks = object["checks"] as? [[String: Any]]
        else { return nil }
        let hasTrack = object["hasTrack"] as? Bool ?? false
        let page = Check(id: "page", ok: true, detail: "", needsTrack: false, hasTrack: hasTrack)
        let checks = rawChecks.compactMap { raw -> Check? in
            guard let id = raw["id"] as? String else { return nil }
            return Check(
                id: id,
                ok: raw["ok"] as? Bool ?? false,
                detail: raw["detail"] as? String ?? "",
                needsTrack: raw["track"] as? Bool ?? false,
                hasTrack: hasTrack
            )
        }
        return PlayerHealthReport(checks: [page] + checks, hasTrack: hasTrack, date: date)
    }
}
