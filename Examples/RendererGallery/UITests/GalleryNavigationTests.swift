import XCTest

final class GalleryNavigationTests: XCTestCase {
    @MainActor
    func testOpenMusicCardAndCapturePlayAction() throws {
        let app = XCUIApplication()
        app.launch()
        let music = app.staticTexts["音乐播放卡"]
        XCTAssertTrue(app.navigationBars["Renderer 样例"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !music.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        music.tap()
        let play = app.buttons["播放"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let callback = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "sample.audio.play"))
        XCTAssertTrue(callback.firstMatch.waitForExistence(timeout: 5))
    }
}
