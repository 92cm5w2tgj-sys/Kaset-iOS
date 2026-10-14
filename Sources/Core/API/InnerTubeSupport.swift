import Foundation

/// From kaset `Services/API/InnerTubeSupport.swift` (the hash lives in `AuthCookies`).
enum InnerTubeSupport {
    /// `client.utcOffsetMinutes`: minutes from UTC, UTC-behind zones negative (LA is `-420`),
    /// matching the web client's `-Date.getTimezoneOffset()`.
    static func utcOffsetMinutes(for timeZone: TimeZone) -> Int {
        timeZone.secondsFromGMT() / 60
    }
}
