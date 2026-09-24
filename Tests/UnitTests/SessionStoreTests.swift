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

    func testPinnedFoldersPersistWithoutDuplicatesAndCanBeRemoved() {
        let suiteName = "ExplorerForMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PinnedFoldersStore(defaults: defaults)
        let documents = URL(fileURLWithPath: "/Users/example/Documents", isDirectory: true)

        XCTAssertTrue(store.pin(documents))
        XCTAssertFalse(store.pin(documents.appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)))
        XCTAssertEqual(store.urls, [documents])
        XCTAssertTrue(store.contains(documents))
        XCTAssertTrue(store.unpin(documents))
        XCTAssertFalse(store.contains(documents))
        XCTAssertTrue(store.urls.isEmpty)
    }
}
