import XCTest

final class PlaybackUITests: XCTestCase {
    @MainActor
    func testDemoPlaybackAndSources() {
        let app = XCUIApplication()
        app.launch()

        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 12))
        pause.tap()
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 4))
        play.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 4))

        app.buttons["Enter full screen"].tap()
        let exitFullScreen = app.buttons["Exit full screen"]
        XCTAssertTrue(exitFullScreen.waitForExistence(timeout: 4))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Constellation on iPad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        exitFullScreen.tap()

        app.buttons["Music source"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Open Audio File"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Follow Apple Music"].firstMatch.exists)
    }
}
