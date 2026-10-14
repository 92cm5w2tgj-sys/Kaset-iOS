import Observation

/// Owns the long-lived services. Later steps add `AuthStore`, the API client and `WebPlayer`.
@MainActor
@Observable
final class AppEnvironment {
    /// The spike's player, kept alive for the whole app lifetime so playback survives
    /// navigating away from the debug lab. Replaced by `WebPlayer` in K4.
    let lab = PlayerModel()

    var isLabPresented = false
}
