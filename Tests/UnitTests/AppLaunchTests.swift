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

    func testDragPasteboardObjectUsesStandardizedFileURL() {
        let url = URL(fileURLWithPath: "/Users/example/Documents/../Desktop/report.txt")

        XCTAssertEqual(
            FileListViewController.dragPasteboardObject(for: url).absoluteURL,
            url.standardizedFileURL
        )
    }

    func testBackgroundContextMenuIncludesNewFolder() {
        let controller = FileListViewController(directoryService: DirectoryService())

        XCTAssertNotNil(
            controller.makeBackgroundContextMenu().items.first(where: { $0.title == "新しいフォルダー" })
        )
    }

    func testItemContextMenuIncludesTrashAction() {
        let controller = FileListViewController(directoryService: DirectoryService())

        XCTAssertNotNil(
            controller.makeItemContextMenu().items.first(where: { $0.title == "ゴミ箱に入れる" })
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

        let appMenu = try XCTUnwrap(application.mainMenu?.items.first?.submenu)
        XCTAssertNotNil(appMenu.items.first(where: { $0.title == "Finder機能拡張を管理…" }))

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

        let fileMenu = try XCTUnwrap(application.mainMenu?.items.first(where: { $0.title == "ファイル" })?.submenu)
        XCTAssertNotNil(fileMenu.items.first(where: { $0.title == "タブを新しいウインドウへ移動" }))

        let buttons = window.contentView.map(allSubviews(in:))?.compactMap { $0 as? NSButton } ?? []
        XCTAssertNotNil(buttons.first(where: { $0.toolTip == "現在のタブを新しいウインドウへ移動" }))
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

    func testHostedExternalFolderOpensInNewTab() throws {
        guard NSApplication.shared.delegate != nil else {
            throw XCTSkip("Swift Packageのテスト実行ではAppKitホストを起動しません。")
        }

        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplorerForMacExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let initialHistory = NavigationHistory(initialURL: FileManager.default.homeDirectoryForCurrentUser)
        let controller = MainWindowController(session: PersistedSession(
            tabs: [initialHistory],
            selectedTabIndex: 0,
            showsHiddenFiles: false
        ))

        XCTAssertTrue(controller.openExternalFolder(folderURL))
        XCTAssertEqual(controller.persistedSession?.tabs.count, 2)
        XCTAssertEqual(controller.persistedSession?.tabs.last?.currentURL, folderURL.standardizedFileURL)
        controller.window?.close()
    }

    func testHostedTabDetachPreservesHistoryAndRemovesItFromSourceWindow() throws {
        guard NSApplication.shared.delegate != nil else {
            throw XCTSkip("Swift Packageのテスト実行ではAppKitホストを起動しません。")
        }

        var firstHistory = NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp/first"))
        firstHistory.navigate(to: URL(fileURLWithPath: "/tmp/first/child"))
        let secondHistory = NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp/second"))
        let controller = MainWindowController(session: PersistedSession(
            tabs: [firstHistory, secondHistory],
            selectedTabIndex: 1,
            showsHiddenFiles: true
        ))
        let coordinator = WindowCoordinatorSpy()
        controller.coordinator = coordinator

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let buttons = allSubviews(in: contentView).compactMap { $0 as? NSButton }
        let detachButton = try XCTUnwrap(
            buttons.first(where: { $0.toolTip == "現在のタブを新しいウインドウへ移動" })
        )
        detachButton.performClick(nil)

        XCTAssertEqual(coordinator.detachedTab?.history, secondHistory)
        XCTAssertEqual(coordinator.detachedTab?.showsHiddenFiles, true)
        XCTAssertEqual(controller.persistedSession?.tabs, [firstHistory])
        controller.window?.close()
    }

    func testHostedAppDelegateCreatesWindowForDetachedTab() throws {
        let application = NSApplication.shared
        guard let appDelegate = application.delegate as? AppDelegate else {
            throw XCTSkip("Swift Packageのテスト実行ではAppKitホストを起動しません。")
        }

        let sourceController = MainWindowController(session: nil)
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let history = NavigationHistory(initialURL: URL(fileURLWithPath: "/tmp"))

        appDelegate.mainWindowController(
            sourceController,
            didDetach: DetachedTabState(history: history, searchQuery: "log", showsHiddenFiles: true),
            at: nil
        )

        let detachedWindow = try XCTUnwrap(
            application.windows.first(where: { !existingWindows.contains(ObjectIdentifier($0)) })
        )
        let detachedController = try XCTUnwrap(detachedWindow.windowController as? MainWindowController)
        XCTAssertTrue(detachedWindow.isVisible)
        XCTAssertEqual(detachedController.persistedSession?.tabs, [history])
        XCTAssertEqual(detachedController.persistedSession?.showsHiddenFiles, true)

        detachedWindow.close()
        sourceController.window?.close()
    }

    private func allSubviews(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(in:))
    }
}

private final class WindowCoordinatorSpy: MainWindowControllerCoordinator {
    var detachedTab: DetachedTabState?

    func mainWindowControllerDidChangeState(_ controller: MainWindowController) {}

    func mainWindowController(
        _ controller: MainWindowController,
        didDetach tab: DetachedTabState,
        at screenPoint: NSPoint?
    ) {
        detachedTab = tab
    }

    func mainWindowControllerWillClose(_ controller: MainWindowController) {}
}
