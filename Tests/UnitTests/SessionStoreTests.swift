import Foundation
import XCTest
@testable import ExplorerForMac

final class SessionStoreTests: XCTestCase {
    func testRoundTrip() {
        let suiteName = "ExplorerForMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SessionStore(defaults: defaults)
        let expected = PersistedSession(
            tabs: [NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp"))],
            selectedTabIndex: 0,
            showsHiddenFiles: true
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }
}
