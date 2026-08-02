import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveSession()
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
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Explorer for Macを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "ファイル"
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "ファイル")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "新規タブ", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t")
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
}
