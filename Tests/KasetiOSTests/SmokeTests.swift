import Testing

@testable import KasetiOS

@MainActor
struct SmokeTests {
    @Test func environmentBoots() {
        let environment = AppEnvironment()
        #expect(environment.isPlaybackDebugPresented == false)
    }
}
