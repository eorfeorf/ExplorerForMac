import Foundation
import XCTest
@testable import ExplorerForMac

final class NavigationHistoryTests: XCTestCase {
    func testNavigationSupportsBackAndForward() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        let third = URL(fileURLWithPath: "/tmp/third")
        var history = NavigationHistory(initialURL: first)

        history.navigate(to: second)
        history.navigate(to: third)

        XCTAssertTrue(history.canGoBack)
        XCTAssertEqual(history.goBack(), second)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.goForward(), second)
    }

    func testNewNavigationRemovesForwardEntries() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        let replacement = URL(fileURLWithPath: "/tmp/replacement")
        var history = NavigationHistory(initialURL: first)
        history.navigate(to: second)
        _ = history.goBack()

        history.navigate(to: replacement)

        XCTAssertEqual(history.currentURL, replacement)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.entries, [first, replacement])
    }

    func testHistoryIsLimitedToOneHundredEntries() {
        var history = NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp/0"))
        for index in 1...120 {
            history.navigate(to: URL(fileURLWithPath: "/tmp/\(index)"))
        }

        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.currentURL.path, "/tmp/120")
    }
}
