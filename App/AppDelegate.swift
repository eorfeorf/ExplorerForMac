import AppKit
import Foundation
import FinderSync

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionStore = SessionStore()
    private var windowControllers: [MainWindowController] = []
    private var pendingFolderURLs: [URL] = []
    private var hasFinishedLaunching = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        hasFinishedLaunching = true
        if let firstFolder = pendingFolderURLs.first {
            let session = PersistedSession(
                tabs: [NavigationHistory(initialURL: firstFolder)],
                selectedTabIndex: 0,
                showsHiddenFiles: false
            )
            showWindow(session: session)
            openPendingFolders(droppingFirst: true)
        } else {
            showWindow(session: sessionStore.load())
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFolderURLs.append(contentsOf: urls.compactMap(Self.folderURL(from:)))
        if hasFinishedLaunching {
            openPendingFolders(droppingFirst: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveOpenWindowSessions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Explorer for Macについて",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "フルディスクアクセス設定を開く…",
            action: #selector(MainWindowController.openFullDiskAccessSettings(_:)),
            keyEquivalent: ""
        )
        let finderExtensionItem = appMenu.addItem(
            withTitle: "Finder機能拡張を管理…",
            action: #selector(openFinderExtensionSettings(_:)),
            keyEquivalent: ""
        )
        finderExtensionItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Explorer for Macを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "ファイル"
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "ファイル")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "新規タブ", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(
            withTitle: "タブを新しいウインドウへ移動",
            action: #selector(MainWindowController.detachCurrentTab(_:)),
            keyEquivalent: ""
        )
        fileMenu.addItem(withTitle: "タブを閉じる", action: #selector(MainWindowController.closeCurrentTab(_:)), keyEquivalent: "w")

        let goMenuItem = NSMenuItem()
        goMenuItem.title = "移動"
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "移動")
        goMenuItem.submenu = goMenu
        let backItem = goMenu.addItem(
            withTitle: "戻る",
            action: #selector(MainWindowController.goBack(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        )
        backItem.keyEquivalentModifierMask = [.command]
        let forwardItem = goMenu.addItem(
            withTitle: "進む",
            action: #selector(MainWindowController.goForward(_:)),
            keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        )
        forwardItem.keyEquivalentModifierMask = [.command]
        let upItem = goMenu.addItem(withTitle: "上へ", action: #selector(MainWindowController.goUp(_:)), keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        upItem.keyEquivalentModifierMask = [.command]
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "パスを入力", action: #selector(MainWindowController.focusAddressBar(_:)), keyEquivalent: "l")
        goMenu.addItem(withTitle: "更新", action: #selector(MainWindowController.refresh(_:)), keyEquivalent: "r")

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "表示"
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "表示")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(
            withTitle: "現在のフォルダーを検索",
            action: #selector(MainWindowController.focusSearchField(_:)),
            keyEquivalent: "f"
        )
        viewMenu.addItem(.separator())
        let hiddenItem = viewMenu.addItem(withTitle: "隠しファイルを表示／非表示", action: #selector(MainWindowController.toggleHiddenFiles(_:)), keyEquivalent: ".")
        hiddenItem.keyEquivalentModifierMask = [.command, .shift]
        let quickLookItem = viewMenu.addItem(withTitle: "Quick Look", action: #selector(MainWindowController.quickLook(_:)), keyEquivalent: " ")
        quickLookItem.keyEquivalentModifierMask = []

        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "ウインドウ"
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        windowMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "拡大／縮小", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    }

    @objc private func openFinderExtensionSettings(_ sender: Any?) {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    private static func folderURL(from url: URL) -> URL? {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? normalized : normalized.deletingLastPathComponent()
    }

    private func openPendingFolders(droppingFirst: Bool) {
        if droppingFirst, !pendingFolderURLs.isEmpty {
            pendingFolderURLs.removeFirst()
        }
        guard !pendingFolderURLs.isEmpty else { return }
        let folders = pendingFolderURLs
        pendingFolderURLs.removeAll()

        let controller = windowControllers.first(where: { $0.window?.isKeyWindow == true })
            ?? windowControllers.first
            ?? showWindow()
        folders.forEach { _ = controller.openExternalFolder($0) }
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    private func showWindow(
        session: PersistedSession? = nil,
        detachedTab: DetachedTabState? = nil,
        near screenPoint: NSPoint? = nil
    ) -> MainWindowController {
        let controller = MainWindowController(session: session, detachedTab: detachedTab)
        controller.coordinator = self
        windowControllers.append(controller)
        controller.showWindow(nil)
        if let screenPoint, let window = controller.window {
            position(window: window, near: screenPoint)
        }
        return controller
    }

    private func position(window: NSWindow, near screenPoint: NSPoint) {
        var frame = window.frame
        frame.origin = NSPoint(
            x: screenPoint.x - min(180, frame.width / 3),
            y: screenPoint.y - frame.height + 24
        )
        if let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) })?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
    }

    private func saveOpenWindowSessions(fallback: PersistedSession? = nil) {
        let controllersWithSessions = windowControllers.compactMap { controller in
            controller.persistedSession.map { (controller, $0) }
        }
        guard !controllersWithSessions.isEmpty else {
            if let fallback { sessionStore.save(fallback) }
            return
        }

        let activeController = controllersWithSessions.first(where: { $0.0.window?.isKeyWindow == true })?.0
            ?? controllersWithSessions[0].0
        var histories: [NavigationHistory] = []
        var selectedTabIndex = 0
        var showsHiddenFiles = false

        for (controller, session) in controllersWithSessions {
            if controller === activeController {
                selectedTabIndex = histories.count + session.selectedTabIndex
                showsHiddenFiles = session.showsHiddenFiles
            }
            histories.append(contentsOf: session.tabs)
        }

        sessionStore.save(PersistedSession(
            tabs: Array(histories.prefix(12)),
            selectedTabIndex: min(selectedTabIndex, max(0, min(histories.count, 12) - 1)),
            showsHiddenFiles: showsHiddenFiles
        ))
    }
}

extension AppDelegate: MainWindowControllerCoordinator {
    func mainWindowControllerDidChangeState(_ controller: MainWindowController) {
        saveOpenWindowSessions()
    }

    func mainWindowController(
        _ controller: MainWindowController,
        didDetach tab: DetachedTabState,
        at screenPoint: NSPoint?
    ) {
        let detachedController = showWindow(detachedTab: tab, near: screenPoint)
        detachedController.window?.makeKeyAndOrderFront(nil)
        saveOpenWindowSessions()
    }

    func mainWindowControllerWillClose(_ controller: MainWindowController) {
        let closingSession = controller.persistedSession
        windowControllers.removeAll { $0 === controller }
        saveOpenWindowSessions(fallback: closingSession)
    }
}
