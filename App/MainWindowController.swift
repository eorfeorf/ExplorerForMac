import AppKit
import Foundation

struct DetachedTabState {
    let history: NavigationHistory
    let searchQuery: String
    let showsHiddenFiles: Bool
}

protocol MainWindowControllerCoordinator: AnyObject {
    func mainWindowControllerDidChangeState(_ controller: MainWindowController)
    func mainWindowController(
        _ controller: MainWindowController,
        didDetach tab: DetachedTabState,
        at screenPoint: NSPoint?
    )
    func mainWindowControllerWillClose(_ controller: MainWindowController)
}

private final class BrowserSession {
    var history: NavigationHistory
    let browserViewController: BrowserViewController

    init(history: NavigationHistory, browserViewController: BrowserViewController) {
        self.history = history
        self.browserViewController = browserViewController
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {
    weak var coordinator: MainWindowControllerCoordinator?

    private let directoryService = DirectoryService()
    private let rootViewController = NSViewController()
    private let tabBar = TabBarView()
    private let addressBar = AddressBarView()
    private let browserContainer = NSView()
    private var sessions: [BrowserSession] = []
    private var selectedSessionIndex = 0
    private var showsHiddenFiles = false

    private var selectedSession: BrowserSession? {
        sessions.indices.contains(selectedSessionIndex) ? sessions[selectedSessionIndex] : nil
    }

    init(session: PersistedSession? = nil, detachedTab: DetachedTabState? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Explorer for Mac"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        super.init(window: window)
        window.delegate = self
        setupRootView()
        window.setContentSize(NSSize(width: 1240, height: 780))
        window.center()
        if let detachedTab {
            restoreDetachedTab(detachedTab)
        } else {
            restoreSession(session)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func saveSession() {
        coordinator?.mainWindowControllerDidChangeState(self)
    }

    var persistedSession: PersistedSession? {
        guard !sessions.isEmpty else { return nil }
        return PersistedSession(
            tabs: sessions.map(\.history),
            selectedTabIndex: selectedSessionIndex,
            showsHiddenFiles: showsHiddenFiles
        )
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.mainWindowControllerWillClose(self)
    }

    @objc func newTab(_ sender: Any?) {
        let initialURL = selectedSession?.history.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
        addSession(history: NavigationHistory(initialURL: initialURL), activate: true)
        saveSession()
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        guard !sessions.isEmpty else { return }
        if sessions.count == 1 {
            window?.performClose(sender)
            return
        }

        let removed = sessions.remove(at: selectedSessionIndex)
        removed.browserViewController.view.removeFromSuperview()
        removed.browserViewController.removeFromParent()
        selectedSessionIndex = min(selectedSessionIndex, sessions.count - 1)
        showSelectedSession()
        saveSession()
    }

    @objc func detachCurrentTab(_ sender: Any?) {
        detachSession(at: selectedSessionIndex, screenPoint: nil)
    }

    @discardableResult
    func openExternalFolder(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        addSession(history: NavigationHistory(initialURL: normalized), activate: true)
        window?.makeKeyAndOrderFront(nil)
        saveSession()
        return true
    }

    @objc func goBack(_ sender: Any?) {
        guard let session = selectedSession, let url = session.history.goBack() else { return }
        display(url: url, in: session)
    }

    @objc func goForward(_ sender: Any?) {
        guard let session = selectedSession, let url = session.history.goForward() else { return }
        display(url: url, in: session)
    }

    @objc func goUp(_ sender: Any?) {
        guard let currentURL = selectedSession?.history.currentURL else { return }
        let parent = currentURL.deletingLastPathComponent()
        guard parent.path != currentURL.path else { return }
        navigate(to: parent)
    }

    @objc func focusAddressBar(_ sender: Any?) {
        addressBar.focusPathField()
    }

    @objc func focusSearchField(_ sender: Any?) {
        addressBar.focusSearchField()
    }

    @objc func refresh(_ sender: Any?) {
        selectedSession?.browserViewController.reload()
    }

    @objc func openCurrentFolderInTerminal(_ sender: Any?) {
        guard let directoryURL = selectedSession?.history.currentURL,
              let terminalURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Terminal"
              ) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: terminalURL,
            configuration: configuration
        )
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        setShowsHiddenFiles(!showsHiddenFiles)
    }

    @objc func quickLook(_ sender: Any?) {
        selectedSession?.browserViewController.showQuickLook()
    }

    @objc func openFullDiskAccessSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private func setupRootView() {
        guard let window else { return }
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootViewController.view = rootView
        window.contentViewController = rootViewController

        tabBar.delegate = self
        addressBar.delegate = self
        browserContainer.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(tabBar)
        rootView.addSubview(addressBar)
        rootView.addSubview(browserContainer)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: rootView.topAnchor),
            addressBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            addressBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            addressBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            browserContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            browserContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            browserContainer.topAnchor.constraint(equalTo: addressBar.bottomAnchor),
            browserContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func restoreSession(_ stored: PersistedSession?) {
        showsHiddenFiles = stored?.showsHiddenFiles ?? false
        // Restoring history must not probe protected folders at application launch.
        // Missing or denied paths are reported inline when their tab is actually shown.
        let histories = stored?.tabs ?? []

        if histories.isEmpty {
            addSession(
                history: NavigationHistory(initialURL: FileManager.default.homeDirectoryForCurrentUser),
                activate: true
            )
        } else {
            for history in histories.prefix(12) {
                addSession(history: history, activate: false)
            }
            selectedSessionIndex = min(max(0, stored?.selectedTabIndex ?? 0), sessions.count - 1)
            showSelectedSession()
        }
    }

    private func restoreDetachedTab(_ tab: DetachedTabState) {
        showsHiddenFiles = tab.showsHiddenFiles
        addSession(history: tab.history, activate: true)
        selectedSession?.browserViewController.setSearchQuery(tab.searchQuery)
        updateNavigationUI()
    }

    private func addSession(history: NavigationHistory, activate: Bool) {
        let browser = BrowserViewController(directoryService: directoryService)
        browser.browserDelegate = self
        rootViewController.addChild(browser)
        let session = BrowserSession(history: history, browserViewController: browser)
        sessions.append(session)
        if activate {
            selectedSessionIndex = sessions.count - 1
            showSelectedSession()
        }
    }

    private func detachSession(at index: Int, screenPoint: NSPoint?) {
        guard sessions.count > 1,
              sessions.indices.contains(index),
              let coordinator else { return }

        let removed = sessions.remove(at: index)
        let detachedTab = DetachedTabState(
            history: removed.history,
            searchQuery: removed.browserViewController.searchQuery,
            showsHiddenFiles: showsHiddenFiles
        )
        removed.browserViewController.view.removeFromSuperview()
        removed.browserViewController.removeFromParent()

        if index < selectedSessionIndex {
            selectedSessionIndex -= 1
        } else if index == selectedSessionIndex {
            selectedSessionIndex = min(index, sessions.count - 1)
        }

        showSelectedSession()
        coordinator.mainWindowController(self, didDetach: detachedTab, at: screenPoint)
        saveSession()
    }

    private func showSelectedSession() {
        guard let session = selectedSession else { return }
        browserContainer.subviews.forEach { $0.removeFromSuperview() }
        let browserView = session.browserViewController.view
        browserView.translatesAutoresizingMaskIntoConstraints = false
        browserContainer.addSubview(browserView)
        NSLayoutConstraint.activate([
            browserView.leadingAnchor.constraint(equalTo: browserContainer.leadingAnchor),
            browserView.trailingAnchor.constraint(equalTo: browserContainer.trailingAnchor),
            browserView.topAnchor.constraint(equalTo: browserContainer.topAnchor),
            browserView.bottomAnchor.constraint(equalTo: browserContainer.bottomAnchor)
        ])
        display(url: session.history.currentURL, in: session)
    }

    private func navigate(to url: URL) {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else {
            presentError(message: "指定した項目が見つかりません。", detail: normalized.path)
            return
        }
        if !isDirectory.boolValue {
            NSWorkspace.shared.open(normalized)
            return
        }
        guard let session = selectedSession else { return }
        session.history.navigate(to: normalized)
        display(url: normalized, in: session)
    }

    private func display(url: URL, in session: BrowserSession) {
        session.browserViewController.load(url: url, showsHiddenFiles: showsHiddenFiles)
        updateNavigationUI()
        saveSession()
    }

    private func setShowsHiddenFiles(_ value: Bool) {
        showsHiddenFiles = value
        for session in sessions {
            session.browserViewController.load(url: session.history.currentURL, showsHiddenFiles: value)
        }
        updateNavigationUI()
        saveSession()
    }

    private func updateNavigationUI() {
        guard let session = selectedSession else { return }
        let url = session.history.currentURL
        addressBar.update(
            path: url.path,
            canGoBack: session.history.canGoBack,
            canGoForward: session.history.canGoForward,
            showsHiddenFiles: showsHiddenFiles,
            searchQuery: session.browserViewController.searchQuery
        )
        tabBar.update(titles: sessions.map { title(for: $0.history.currentURL) }, selectedIndex: selectedSessionIndex)
        window?.representedURL = url
        window?.title = "\(title(for: url)) — Explorer for Mac"
    }

    private func title(for url: URL) -> String {
        if url.path == "/" { return "/" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func pathURL(from input: String) -> URL {
        let expanded = (input as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        let baseURL = selectedSession?.history.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
        return baseURL.appendingPathComponent(expanded)
    }

    private func presentError(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

extension MainWindowController: AddressBarViewDelegate {
    func addressBarDidRequestBack(_ addressBar: AddressBarView) {
        goBack(addressBar)
    }

    func addressBarDidRequestForward(_ addressBar: AddressBarView) {
        goForward(addressBar)
    }

    func addressBarDidRequestUp(_ addressBar: AddressBarView) {
        goUp(addressBar)
    }

    func addressBar(_ addressBar: AddressBarView, didSubmitPath path: String) {
        navigate(to: pathURL(from: path))
    }

    func addressBar(_ addressBar: AddressBarView, didRequestNavigateTo url: URL) {
        navigate(to: url)
    }

    func addressBarDidRequestRefresh(_ addressBar: AddressBarView) {
        refresh(addressBar)
    }

    func addressBarDidRequestOpenCurrentFolderInTerminal(_ addressBar: AddressBarView) {
        openCurrentFolderInTerminal(addressBar)
    }

    func addressBar(_ addressBar: AddressBarView, didChangeHiddenFilesVisibility isVisible: Bool) {
        setShowsHiddenFiles(isVisible)
    }

    func addressBar(_ addressBar: AddressBarView, didChangeSearchQuery query: String) {
        selectedSession?.browserViewController.setSearchQuery(query)
    }

    func addressBarDidRequestFullDiskAccessSettings(_ addressBar: AddressBarView) {
        openFullDiskAccessSettings(addressBar)
    }
}

extension MainWindowController: TabBarViewDelegate {
    func tabBar(_ tabBar: TabBarView, didSelect index: Int) {
        guard sessions.indices.contains(index) else { return }
        selectedSessionIndex = index
        showSelectedSession()
    }

    func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        newTab(tabBar)
    }

    func tabBar(_ tabBar: TabBarView, didRequestDetach index: Int, at screenPoint: NSPoint?) {
        detachSession(at: index, screenPoint: screenPoint)
    }

    func tabBarDidRequestCloseCurrentTab(_ tabBar: TabBarView) {
        closeCurrentTab(tabBar)
    }
}

extension MainWindowController: BrowserViewControllerDelegate {
    func browser(_ browser: BrowserViewController, didRequestNavigateTo url: URL) {
        guard browser === selectedSession?.browserViewController else { return }
        navigate(to: url)
    }

    func browser(_ browser: BrowserViewController, didRequestOpenInNewTab url: URL) {
        guard browser === selectedSession?.browserViewController else { return }
        addSession(history: NavigationHistory(initialURL: url), activate: true)
        saveSession()
    }
}
