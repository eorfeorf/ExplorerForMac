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
}
