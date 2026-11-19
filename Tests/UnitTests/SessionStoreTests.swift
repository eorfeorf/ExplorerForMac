import Foundation
import XCTest
@testable import ExplorerForMac

final class SessionStoreTests: XCTestCase {
    func testSortOrdersPersistPerFolder() {
        let suiteName = "ExplorerForMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = URL(fileURLWithPath: "/tmp/folder-a", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/folder-b", isDirectory: true)
        let store = FolderSortStore(defaults: defaults)
        let order = FolderSortOrder(column: .modifiedAt, ascending: false)
        store.setOrder(order, for: first)

        let reloaded = FolderSortStore(defaults: defaults)
        XCTAssertEqual(reloaded.order(for: first.appendingPathComponent("../folder-a")), order)
        XCTAssertEqual(reloaded.order(for: second), .default)
        reloaded.setOrder(FolderSortOrder(column: .size, ascending: true), for: second)
        XCTAssertEqual(store.order(for: first), order)
        XCTAssertEqual(store.order(for: second), FolderSortOrder(column: .size, ascending: true))
    }

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

    func testLegacySessionEnablesHiddenFilesOnceAndPreservesLaterChoice() throws {
        let suiteName = "ExplorerForMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = PersistedSession(
            tabs: [NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp"))],
            selectedTabIndex: 0,
            showsHiddenFiles: false
        )
        defaults.set(try JSONEncoder().encode(original), forKey: "ExplorerForMac.session.v1")
        let store = SessionStore(defaults: defaults)
        let migrated = try XCTUnwrap(store.load())
        XCTAssertEqual(migrated.tabs, original.tabs)
        XCTAssertEqual(migrated.selectedTabIndex, original.selectedTabIndex)
        XCTAssertTrue(migrated.showsHiddenFiles)

        store.save(original)
        XCTAssertEqual(store.load(), original)
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

    func testRelocateUpdatesPinnedDescendants() {
        let suiteName = "ExplorerForMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PinnedFoldersStore(defaults: defaults)
        store.pin(URL(fileURLWithPath: "/tmp/old/child"))
        store.pin(URL(fileURLWithPath: "/tmp/older"))
        store.relocate(from: URL(fileURLWithPath: "/tmp/old"), to: URL(fileURLWithPath: "/tmp/new"))
        XCTAssertEqual(store.urls.map(\.path), ["/tmp/new/child", "/tmp/older"])
    }
}
