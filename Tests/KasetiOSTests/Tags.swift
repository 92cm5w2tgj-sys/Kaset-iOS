import Testing

extension Tag {
    @Tag static var parser: Self
}

/// Anchors `Bundle(for:)` to the test bundle so fixtures can be found.
final class FixtureBundleToken {}
