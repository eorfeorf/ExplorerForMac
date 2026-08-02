import AppKit
import XCTest
@testable import ExplorerForMac

final class AppLaunchTests: XCTestCase {
    func testFolderSearchMatchesNamesNaturally() {
        XCTAssertTrue(FileListViewController.itemName("重要書類.PDF", matchesSearchQuery: "書類"))
        XCTAssertTrue(FileListViewController.itemName("Résumé.txt", matchesSearchQuery: "resume"))
        XCTAssertTrue(FileListViewController.itemName("ＡＢＣ.txt", matchesSearchQuery: "abc"))
        XCTAssertTrue(FileListViewController.itemName("anything", matchesSearchQuery: "   "))
        XCTAssertFalse(FileListViewController.itemName("photo.png", matchesSearchQuery: "report"))
    }

    func testBreadcrumbsContainEveryPathLevel() {
        let url = URL(fileURLWithPath: "/Users/example/Documents/Reports", isDirectory: true)

        XCTAssertEqual(
            AddressBarView.breadcrumbURLs(for: url).map(\.path),
            ["/", "/Users", "/Users/example", "/Users/example/Documents", "/Users/example/Documents/Reports"]
        )
    }

    func testHostedApplicationCreatesMainWindow() throws {
        let application = NSApplication.shared
        guard application.delegate != nil else {
            throw XCTSkip("Swift Packageのテスト実行ではAppKitホストを起動しません。")
        }

        XCTAssertTrue(application.delegate is AppDelegate)
        let window = try XCTUnwrap(application.windows.first(where: { $0.title.contains("Explorer for Mac") }))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, true)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isHidden, true)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true)

        let goMenu = try XCTUnwrap(application.mainMenu?.items.first(where: { $0.title == "移動" })?.submenu)
        let backItem = try XCTUnwrap(goMenu.items.first(where: { $0.title == "戻る" }))
        let forwardItem = try XCTUnwrap(goMenu.items.first(where: { $0.title == "進む" }))
        let upItem = try XCTUnwrap(goMenu.items.first(where: { $0.title == "上へ" }))
        XCTAssertEqual(backItem.keyEquivalent, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        XCTAssertEqual(backItem.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(forwardItem.keyEquivalent, String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        XCTAssertEqual(forwardItem.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(upItem.keyEquivalent, String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        XCTAssertEqual(upItem.keyEquivalentModifierMask, [.command])

        let buttons = window.contentView.map(allSubviews(in:))?.compactMap { $0 as? NSButton } ?? []
        for label in ["ウインドウをしまう", "最大化／元に戻す", "ウインドウを閉じる"] {
            let button = try XCTUnwrap(buttons.first(where: { $0.toolTip == label }))
            XCTAssertTrue(button.constraints.contains(where: {
                $0.isActive
                    && $0.firstAttribute == .height
                    && $0.relation == .equal
                    && $0.secondItem == nil
                    && $0.constant == 38
            }))
        }
    }

    private func allSubviews(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(in:))
    }
}
