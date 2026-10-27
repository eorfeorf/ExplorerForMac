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

    func testCreateTextFileSuggestsUniqueNamesAndNeverOverwrites() throws {
        let service = DirectoryService()
        let firstName = service.suggestedTextFileName(in: temporaryDirectory)
        let first = try service.createTextFile(named: firstName, in: temporaryDirectory)
        try Data("keep".utf8).write(to: first)
        XCTAssertEqual(service.suggestedTextFileName(in: temporaryDirectory), "新しいテキスト ドキュメント (2).txt")
        XCTAssertThrowsError(try service.createTextFile(named: firstName, in: temporaryDirectory))
        XCTAssertEqual(try Data(contentsOf: first), Data("keep".utf8))
        XCTAssertThrowsError(try service.createTextFile(named: "../escape", in: temporaryDirectory))
        XCTAssertThrowsError(try service.createTextFile(named: " ", in: temporaryDirectory))
        let second = try service.createTextFile(named: "メモ", in: temporaryDirectory)
        XCTAssertEqual(second.lastPathComponent, "メモ.txt")
        XCTAssertEqual(try Data(contentsOf: second), Data())
    }

    func testCopyMoveAndRenamePreserveFilesAndRejectConflicts() throws {
        let service = DirectoryService()
        let source = temporaryDirectory.appendingPathComponent("report.txt")
        let folder = temporaryDirectory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("original".utf8).write(to: source)
        let duplicate = try service.transferItem(at: source, to: temporaryDirectory, moving: false)
        XCTAssertEqual(duplicate.lastPathComponent, "report - コピー.txt")
        let copied = try service.transferItem(at: source, to: folder, moving: false)
        XCTAssertEqual(try Data(contentsOf: copied), Data("original".utf8))
        XCTAssertThrowsError(try service.transferItem(at: source, to: folder, moving: true))
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
        let renamed = try service.renameItem(at: duplicate, to: "renamed.txt")
        XCTAssertThrowsError(try service.renameItem(at: renamed, to: "report.txt"))
        XCTAssertThrowsError(try service.renameItem(at: renamed, to: "../outside"))
        let moved = try service.transferItem(at: renamed, to: folder, moving: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertEqual(try Data(contentsOf: moved), Data("original".utf8))
    }

    func testTransferRejectsFolderIntoItselfIncludingSymlinkDestination() throws {
        let service = DirectoryService()
        let source = temporaryDirectory.appendingPathComponent("folder", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        let link = temporaryDirectory.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        XCTAssertThrowsError(try service.transferItem(at: source, to: child, moving: false))
        XCTAssertThrowsError(try service.transferItem(at: source, to: link, moving: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
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
