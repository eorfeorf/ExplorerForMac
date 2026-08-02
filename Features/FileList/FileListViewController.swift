import AppKit
import QuickLookUI

protocol FileListViewControllerDelegate: AnyObject {
    func fileList(_ fileList: FileListViewController, didRequestOpen item: FileItem)
    func fileList(_ fileList: FileListViewController, didRequestOpenInNewTab url: URL)
    func fileList(_ fileList: FileListViewController, didSelect item: FileItem?)
}

private final class ExplorerTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event) ?? super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onQuickLook?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onOpen?()
            return
        }
        super.keyDown(with: event)
    }
}

final class FileListViewController: NSViewController {
    weak var delegate: FileListViewControllerDelegate?

    private let directoryService: DirectoryService
    private let watcher = DirectoryWatcher()
    private let tableView = ExplorerTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let permissionButton = NSButton(title: "フルディスクアクセス設定を開く…", target: nil, action: nil)
    private var allItems: [FileItem] = []
    private var items: [FileItem] = []
    private var currentDirectory: URL?
    private var showsHiddenFiles = false
    private var searchQuery = ""
    private var hasLoadedSnapshot = false
    private var loadIdentifier = UUID()
    private var reloadWorkItem: DispatchWorkItem?
    private var sharingServicePicker: NSSharingServicePicker?
    private var watchedDirectory: URL?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    init(directoryService: DirectoryService) {
        self.directoryService = directoryService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        setupTable()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.setAccessibilityLabel("フォルダーの状態")

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isHidden = true

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        permissionButton.target = self
        permissionButton.action = #selector(openFullDiskAccessSettings)
        permissionButton.isHidden = true

        view.addSubview(scrollView)
        view.addSubview(statusLabel)
        view.addSubview(messageLabel)
        view.addSubview(progressIndicator)
        view.addSubview(permissionButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            statusLabel.heightAnchor.constraint(equalToConstant: 18),
            messageLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, multiplier: 0.75),
            permissionButton.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            permissionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
            progressIndicator.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    deinit {
        watcher.stop()
        reloadWorkItem?.cancel()
    }

    func load(directory: URL, showsHiddenFiles: Bool, searchQuery: String) {
        let normalized = directory.standardizedFileURL
        if currentDirectory != normalized {
            watcher.stop()
            watchedDirectory = nil
            allItems = []
            items = []
            hasLoadedSnapshot = false
            tableView.reloadData()
        }
        currentDirectory = normalized
        self.showsHiddenFiles = showsHiddenFiles
        self.searchQuery = Self.normalizedSearchQuery(searchQuery)
        loadCurrentDirectory(showProgress: true)
    }

    func reload() {
        loadCurrentDirectory(showProgress: false)
    }

    func setSearchQuery(_ query: String) {
        let normalized = Self.normalizedSearchQuery(query)
        guard searchQuery != normalized else { return }
        searchQuery = normalized
        guard hasLoadedSnapshot else { return }
        applySearchAndReload()
    }

    static func itemName(_ itemName: String, matchesSearchQuery query: String) -> Bool {
        let normalized = normalizedSearchQuery(query)
        guard !normalized.isEmpty else { return true }
        return itemName.range(
            of: normalized,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ) != nil
    }

    func showQuickLook() {
        guard !selectedItems.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    private var selectedItems: [FileItem] {
        tableView.selectedRowIndexes.compactMap { index in
            items.indices.contains(index) ? items[index] : nil
        }
    }

    private func setupTable() {
        let columnDefinitions: [(String, String, CGFloat, NSSortDescriptor)] = [
            ("name", "名前", 280, NSSortDescriptor(key: "name", ascending: true)),
            ("modifiedAt", "更新日時", 165, NSSortDescriptor(key: "modifiedAt", ascending: false)),
            ("kind", "種類", 150, NSSortDescriptor(key: "kind", ascending: true)),
            ("size", "サイズ", 100, NSSortDescriptor(key: "size", ascending: false))
        ]
        for (identifier, title, width, sortDescriptor) in columnDefinitions {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "name" ? 150 : 80
            column.sortDescriptorPrototype = sortDescriptor
            tableView.addTableColumn(column)
        }

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowSizeStyle = .medium
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(openSelection)
        tableView.target = self
        tableView.setAccessibilityLabel("ファイル一覧")
        tableView.onOpen = { [weak self] in self?.openSelection() }
        tableView.onQuickLook = { [weak self] in self?.showQuickLook() }
        tableView.contextMenuProvider = { [weak self] event in
            self?.makeContextMenu(for: event)
        }
    }

    private func makeContextMenu(for event: NSEvent) -> NSMenu? {
        let location = tableView.convert(event.locationInWindow, from: nil)
        let clickedRow = tableView.row(at: location)

        if clickedRow >= 0 {
            if !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
            return makeItemContextMenu()
        }

        tableView.deselectAll(nil)
        return makeBackgroundContextMenu()
    }

    private func makeItemContextMenu() -> NSMenu {
        let menu = NSMenu(title: "項目")
        let selection = selectedItems
        let singleItem = selection.count == 1 ? selection[0] : nil

        menu.addItem(makeMenuItem(
            title: selection.count > 1 ? "選択した項目を開く" : "開く",
            symbol: "arrow.up.forward.app",
            action: #selector(openSelectedItems)
        ))

        if let singleItem, singleItem.canBrowse {
            menu.addItem(makeMenuItem(
                title: "新規タブで開く",
                symbol: "plus.rectangle.on.rectangle",
                action: #selector(openSelectionInNewTab)
            ))
        }

        if let singleItem, !singleItem.canBrowse {
            let openWithItem = makeMenuItem(
                title: "このアプリケーションで開く",
                symbol: "app.badge",
                action: nil
            )
            openWithItem.submenu = makeOpenWithMenu(for: singleItem)
            menu.addItem(openWithItem)
        }

        menu.addItem(makeMenuItem(
            title: "Quick Look",
            symbol: "eye",
            action: #selector(showQuickLookFromMenu),
            keyEquivalent: " ",
            modifierMask: []
        ))
        menu.addItem(.separator())

        menu.addItem(makeMenuItem(
            title: "コピー",
            symbol: "doc.on.doc",
            action: #selector(copyItems),
            keyEquivalent: "c"
        ))
        menu.addItem(makeMenuItem(
            title: selection.count > 1 ? "名前をコピー" : "ファイル名をコピー",
            symbol: "textformat",
            action: #selector(copyNames)
        ))
        menu.addItem(makeMenuItem(
            title: "パスをコピー",
            symbol: "link",
            action: #selector(copyPath)
        ))
        menu.addItem(.separator())

        menu.addItem(makeMenuItem(
            title: "Finderで表示",
            symbol: "folder",
            action: #selector(revealSelection)
        ))
        if selection.count == 1 {
            menu.addItem(makeMenuItem(
                title: singleItem?.canBrowse == true ? "このフォルダーをターミナルで開く" : "親フォルダーをターミナルで開く",
                symbol: "terminal",
                action: #selector(openSelectionInTerminal)
            ))
        }
        menu.addItem(makeMenuItem(
            title: "共有…",
            symbol: "square.and.arrow.up",
            action: #selector(shareSelection)
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "プロパティ",
            symbol: "info.circle",
            action: #selector(showProperties)
        ))
        return menu
    }

    private func makeBackgroundContextMenu() -> NSMenu {
        let menu = NSMenu(title: "フォルダー")
        menu.addItem(makeMenuItem(
            title: "更新",
            symbol: "arrow.clockwise",
            action: #selector(refreshFromMenu)
        ))
        menu.addItem(makeMenuItem(
            title: "このフォルダーを新規タブで開く",
            symbol: "plus.rectangle.on.rectangle",
            action: #selector(openCurrentDirectoryInNewTab)
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "Finderで表示",
            symbol: "folder",
            action: #selector(revealCurrentDirectory)
        ))
        menu.addItem(makeMenuItem(
            title: "ターミナルで開く",
            symbol: "terminal",
            action: #selector(openCurrentDirectoryInTerminal)
        ))
        menu.addItem(makeMenuItem(
            title: "パスをコピー",
            symbol: "link",
            action: #selector(copyCurrentDirectoryPath)
        ))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: "プロパティ",
            symbol: "info.circle",
            action: #selector(showCurrentDirectoryProperties)
        ))
        return menu
    }

    private func makeOpenWithMenu(for item: FileItem) -> NSMenu {
        let menu = NSMenu(title: "このアプリケーションで開く")
        let applications = NSWorkspace.shared.urlsForApplications(toOpen: item.url)
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
            .sorted {
                $0.deletingPathExtension().lastPathComponent.localizedStandardCompare(
                    $1.deletingPathExtension().lastPathComponent
                ) == .orderedAscending
            }

        if applications.isEmpty {
            let unavailable = NSMenuItem(title: "利用可能なアプリケーションがありません", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            menu.addItem(unavailable)
            return menu
        }

        for applicationURL in applications.prefix(15) {
            let title = applicationURL.deletingPathExtension().lastPathComponent
            let applicationItem = NSMenuItem(
                title: title,
                action: #selector(openWithApplication(_:)),
                keyEquivalent: ""
            )
            applicationItem.target = self
            applicationItem.representedObject = applicationURL
            applicationItem.image = menuIcon(NSWorkspace.shared.icon(forFile: applicationURL.path))
            menu.addItem(applicationItem)
        }
        return menu
    }

    private func makeMenuItem(
        title: String,
        symbol: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifierMask
        }
        return item
    }

    private func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func loadCurrentDirectory(showProgress: Bool) {
        guard let currentDirectory else { return }
        let identifier = UUID()
        loadIdentifier = identifier
        messageLabel.isHidden = true
        permissionButton.isHidden = true
        if showProgress {
            progressIndicator.startAnimation(nil)
        }

        directoryService.loadContents(of: currentDirectory, showsHiddenFiles: showsHiddenFiles) { [weak self] result in
            guard let self, self.loadIdentifier == identifier else { return }
            self.progressIndicator.stopAnimation(nil)
            switch result {
            case .success(let snapshot):
                self.allItems = snapshot.items
                self.hasLoadedSnapshot = true
                self.beginWatchingIfNeeded(snapshot.directoryURL)
                self.applySearchAndReload()
                self.permissionButton.isHidden = true
            case .failure(let error):
                self.allItems = []
                self.items = []
                self.hasLoadedSnapshot = false
                self.tableView.reloadData()
                self.statusLabel.stringValue = "読み込みに失敗しました"
                let isPermissionError = self.isPermissionError(error)
                self.messageLabel.stringValue = isPermissionError
                    ? "このフォルダーへのアクセスが許可されていません。\n必要な場合は、システム設定で一度だけ許可してください。"
                    : error.localizedDescription
                self.messageLabel.isHidden = false
                self.permissionButton.isHidden = !isPermissionError
                self.delegate?.fileList(self, didSelect: nil)
            }
        }
    }

    private static func normalizedSearchQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySearchAndReload() {
        if searchQuery.isEmpty {
            items = allItems
        } else {
            items = allItems.filter { Self.itemName($0.name, matchesSearchQuery: searchQuery) }
        }

        sortItems(using: tableView.sortDescriptors)
        tableView.deselectAll(nil)
        tableView.reloadData()
        updateStatusLabel()

        if items.isEmpty {
            messageLabel.stringValue = searchQuery.isEmpty
                ? "このフォルダーは空です"
                : "「\(searchQuery)」に一致する項目はありません"
            messageLabel.isHidden = false
        } else {
            messageLabel.stringValue = ""
            messageLabel.isHidden = true
        }
        permissionButton.isHidden = true
        delegate?.fileList(self, didSelect: nil)
    }

    private func updateStatusLabel(selectedCount: Int = 0) {
        let baseText = searchQuery.isEmpty
            ? "\(items.count) 個の項目"
            : "\(items.count) 個が一致（全 \(allItems.count) 個）"
        statusLabel.stringValue = selectedCount > 0
            ? "\(baseText)（\(selectedCount) 個を選択）"
            : baseText
    }

    private func beginWatchingIfNeeded(_ directoryURL: URL) {
        guard watchedDirectory != directoryURL else { return }
        watchedDirectory = directoryURL
        watcher.watch(url: directoryURL) { [weak self] in
            self?.scheduleReload()
        }
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && (cocoaError.code == NSFileReadNoPermissionError || cocoaError.code == NSFileReadNoSuchFileError)
            && currentDirectory.map { Self.isPrivacyProtectedURL($0) } == true
    }

    private static func isPrivacyProtectedURL(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let protectedDirectories = ["Desktop", "Documents", "Downloads"]
            .map { home.appendingPathComponent($0, isDirectory: true).standardizedFileURL.path }
        return protectedDirectories.contains { protectedPath in
            url.path == protectedPath || url.path.hasPrefix(protectedPath + "/")
        }
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadCurrentDirectory(showProgress: false)
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func sortItems(using descriptors: [NSSortDescriptor]) {
        let descriptor = descriptors.first ?? NSSortDescriptor(key: "name", ascending: true)
        let key = descriptor.key ?? "name"
        let ascending = descriptor.ascending

        items.sort { left, right in
            if left.canBrowse != right.canBrowse {
                return left.canBrowse
            }
            let comparison: ComparisonResult
            switch key {
            case "modifiedAt":
                comparison = (left.modifiedAt ?? .distantPast).compare(right.modifiedAt ?? .distantPast)
            case "kind":
                comparison = left.kind.localizedStandardCompare(right.kind)
            case "size":
                let leftSize = left.size ?? -1
                let rightSize = right.size ?? -1
                comparison = leftSize == rightSize ? .orderedSame : (leftSize < rightSize ? .orderedAscending : .orderedDescending)
            default:
                comparison = left.name.localizedStandardCompare(right.name)
            }
            if comparison == .orderedSame {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    @objc private func openSelection() {
        guard tableView.selectedRow >= 0, items.indices.contains(tableView.selectedRow) else { return }
        delegate?.fileList(self, didRequestOpen: items[tableView.selectedRow])
    }

    @objc private func openSelectedItems() {
        let selection = selectedItems
        guard !selection.isEmpty else { return }
        if selection.count == 1, let item = selection.first {
            delegate?.fileList(self, didRequestOpen: item)
            return
        }

        for item in selection {
            if item.canBrowse {
                delegate?.fileList(self, didRequestOpenInNewTab: item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    @objc private func openSelectionInNewTab() {
        guard selectedItems.count == 1, let item = selectedItems.first, item.canBrowse else { return }
        delegate?.fileList(self, didRequestOpenInNewTab: item.url)
    }

    @objc private func openCurrentDirectoryInNewTab() {
        guard let currentDirectory else { return }
        delegate?.fileList(self, didRequestOpenInNewTab: currentDirectory)
    }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL,
              selectedItems.count == 1,
              let item = selectedItems.first else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [item.url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    @objc private func showQuickLookFromMenu() {
        showQuickLook()
    }

    @objc private func revealSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func revealCurrentDirectory() {
        guard let currentDirectory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([currentDirectory])
    }

    @objc private func copyItems() {
        let urls = selectedItems.map(\.url) as [NSURL]
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
    }

    @objc private func copyNames() {
        let names = selectedItems.map(\.name).joined(separator: "\n")
        writeTextToPasteboard(names)
    }

    @objc private func copyPath() {
        let paths = selectedItems.map { $0.url.path }.joined(separator: "\n")
        writeTextToPasteboard(paths)
    }

    @objc private func copyCurrentDirectoryPath() {
        guard let currentDirectory else { return }
        writeTextToPasteboard(currentDirectory.path)
    }

    @objc private func refreshFromMenu() {
        reload()
    }

    @objc private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSelectionInTerminal() {
        guard selectedItems.count == 1, let item = selectedItems.first else { return }
        openInTerminal(directory: item.canBrowse ? item.url : currentDirectory)
    }

    @objc private func openCurrentDirectoryInTerminal() {
        openInTerminal(directory: currentDirectory)
    }

    @objc private func shareSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingServicePicker = picker
        let row = max(0, tableView.selectedRow)
        let anchorRect = tableView.rect(ofRow: row)
        picker.show(relativeTo: anchorRect, of: tableView, preferredEdge: .minY)
    }

    @objc private func showProperties() {
        presentProperties(for: selectedItems)
    }

    @objc private func showCurrentDirectoryProperties() {
        guard let currentDirectory, let item = try? FileItem.load(from: currentDirectory) else { return }
        presentProperties(for: [item])
    }

    private func writeTextToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openInTerminal(directory: URL?) {
        guard let directory,
              let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminalURL,
            configuration: configuration
        )
    }

    private func presentProperties(for selection: [FileItem]) {
        guard !selection.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "閉じる")

        if selection.count == 1, let item = selection.first {
            alert.messageText = item.name
            var details = [
                "種類: \(item.kind)",
                "場所: \(item.url.deletingLastPathComponent().path)"
            ]
            if let size = item.size {
                details.append("サイズ: \(sizeFormatter.string(fromByteCount: size))（\(size) バイト）")
            }
            if let modifiedAt = item.modifiedAt {
                details.append("更新日時: \(dateFormatter.string(from: modifiedAt))")
            }
            if item.isSymbolicLink {
                details.append("シンボリックリンク: はい")
            }
            details.append("フルパス: \(item.url.path)")
            alert.informativeText = details.joined(separator: "\n")
        } else {
            let folderCount = selection.filter(\.canBrowse).count
            let fileCount = selection.count - folderCount
            let totalSize = selection.compactMap(\.size).reduce(0, +)
            alert.messageText = "\(selection.count) 個の項目"
            alert.informativeText = [
                "フォルダー: \(folderCount)",
                "ファイル: \(fileCount)",
                "ファイルの合計サイズ: \(sizeFormatter.string(fromByteCount: totalSize))"
            ].joined(separator: "\n")
        }

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

extension FileListViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

extension FileListViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, items.indices.contains(row) else { return nil }
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("Cell-\(tableColumn.identifier.rawValue)")
        let cell: NSTableCellView

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = makeCell(identifier: identifier, includesIcon: tableColumn.identifier.rawValue == "name")
        }

        switch tableColumn.identifier.rawValue {
        case "name":
            cell.textField?.stringValue = item.name
            cell.textField?.toolTip = item.url.path
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        case "modifiedAt":
            cell.textField?.stringValue = item.modifiedAt.map(dateFormatter.string) ?? "—"
        case "kind":
            cell.textField?.stringValue = item.isSymbolicLink ? "\(item.kind)（リンク）" : item.kind
        case "size":
            cell.textField?.stringValue = item.size.map(sizeFormatter.string) ?? "—"
            cell.textField?.alignment = .right
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        let item = row >= 0 && items.indices.contains(row) ? items[row] : nil
        delegate?.fileList(self, didSelect: item)
        let selectedCount = tableView.selectedRowIndexes.count
        updateStatusLabel(selectedCount: selectedCount)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortItems(using: tableView.sortDescriptors)
        tableView.reloadData()
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier, includesIcon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        cell.textField = textField
        cell.addSubview(textField)

        if includesIcon {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.imageView = imageView
            cell.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6)
            ])
        } else {
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
        }

        NSLayoutConstraint.activate([
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

extension FileListViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let selectedItems = selectedItems
        guard selectedItems.indices.contains(index) else { return nil }
        return selectedItems[index].url as NSURL
    }
}
