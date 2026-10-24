import XCTest

// The fastlane way: one UI test that relaunches the app into each screen and calls snapshot().
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testScreenshots() {
        for screen in ["Welcome", "Habit list", "Stats", "Settings", "Root"] {
            let app = XCUIApplication()
            setupSnapshot(app)
            app.launchArguments += ["-FastlaneScreen", screen]
            app.launch()
            snapshot(screen)
        }
    }
}
