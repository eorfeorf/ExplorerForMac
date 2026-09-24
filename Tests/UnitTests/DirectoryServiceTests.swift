import Foundation
import XCTest
@testable import ExplorerForMac

final class DirectoryServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testContentsReadsFilesAndDirectories() throws {
        let folder = temporaryDirectory.appendingPathComponent("Folder", isDirectory: true)
        let file = temporaryDirectory.appendingPathComponent("hello.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: file)

        let snapshot = try DirectoryService().contents(of: temporaryDirectory, showsHiddenFiles: false)

        XCTAssertEqual(Set(snapshot.items.map(\.name)), ["Folder", "hello.txt"])
        XCTAssertEqual(snapshot.items.first(where: { $0.name == "Folder" })?.canBrowse, true)
        XCTAssertEqual(snapshot.items.first(where: { $0.name == "hello.txt" })?.size, 5)
    }

    func testHiddenFilesCanBeFiltered() throws {
        let hiddenFile = temporaryDirectory.appendingPathComponent(".secret")
        try Data().write(to: hiddenFile)

        let hidden = try DirectoryService().contents(of: temporaryDirectory, showsHiddenFiles: false)
        let visible = try DirectoryService().contents(of: temporaryDirectory, showsHiddenFiles: true)

        XCTAssertFalse(hidden.items.contains(where: { $0.name == ".secret" }))
        XCTAssertTrue(visible.items.contains(where: { $0.name == ".secret" }))
    }

    func testFileURLIsRejectedAsDirectory() throws {
        let file = temporaryDirectory.appendingPathComponent("file")
        try Data().write(to: file)

        XCTAssertThrowsError(try DirectoryService().contents(of: file, showsHiddenFiles: false))
    }

    func testSuggestedFolderNameUsesWindowsStyleSuffix() throws {
        let service = DirectoryService()
        try service.createFolder(named: "新しいフォルダー", in: temporaryDirectory)
        try service.createFolder(named: "新しいフォルダー (2)", in: temporaryDirectory)

        XCTAssertEqual(
            service.suggestedFolderName(in: temporaryDirectory),
            "新しいフォルダー (3)"
        )
    }

    func testCreateFolderValidatesNameAndRejectsDuplicates() throws {
        let service = DirectoryService()
        let folderURL = try service.createFolder(named: "資料", in: temporaryDirectory)
        var isDirectory: ObjCBool = false

        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertThrowsError(try service.createFolder(named: "資料", in: temporaryDirectory))
        XCTAssertThrowsError(try service.createFolder(named: "../資料", in: temporaryDirectory))
        XCTAssertThrowsError(try service.createFolder(named: "   ", in: temporaryDirectory))
    }

    func testTrashItemsMovesMultipleItemsToTrash() throws {
        let first = temporaryDirectory.appendingPathComponent("first.txt")
        let second = temporaryDirectory.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let movedURLs = try DirectoryService().trashItems(at: [first, second])
        defer {
            movedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(movedURLs.count, 2)
    }
}
