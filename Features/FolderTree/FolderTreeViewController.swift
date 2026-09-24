import AppKit
import Foundation

protocol FolderTreeViewControllerDelegate: AnyObject {
    func folderTree(_ folderTree: FolderTreeViewController, didSelect url: URL)
}

private final class SidebarOutlineView: NSOutlineView {
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event) ?? super.menu(for: event)
    }
}

private final class SidebarItem {
    let url: URL
    let title: String
    let isPlaceholder: Bool
    let isSection: Bool
    let isPinned: Bool
    var children: [SidebarItem] = []
    var hasLoadedChildren = false
    var isLoading = false

    init(
        url: URL,
        title: String? = nil,
        isPlaceholder: Bool = false,
        isSection: Bool = false,
        isPinned: Bool = false
    ) {
        self.url = url
        self.title = title ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.isPlaceholder = isPlaceholder
        self.isSection = isSection
        self.isPinned = isPinned
        hasLoadedChildren = isSection
    }

    convenience init(sectionTitle: String, children: [SidebarItem]) {
        self.init(url: URL(fileURLWithPath: "/", isDirectory: true), title: sectionTitle, isSection: true)
        self.children = children
    }
}

final class FolderTreeViewController: NSViewController {
    weak var delegate: FolderTreeViewControllerDelegate?
    var showsHiddenFiles = false {
        didSet { reloadRoots() }
    }

    private let directoryService: DirectoryService
    private let pinnedFoldersStore = PinnedFoldersStore.shared
    private let outlineView = SidebarOutlineView()
    private let scrollView = NSScrollView()
    private var roots: [SidebarItem] = []
    private var pinnedFoldersObserver: NSObjectProtocol?

    init(directoryService: DirectoryService) {
        self.directoryService = directoryService
        super.init(nibName: nil, bundle: nil)
        pinnedFoldersObserver = NotificationCenter.default.addObserver(
            forName: PinnedFoldersStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadRoots()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let pinnedFoldersObserver {
            NotificationCenter.default.removeObserver(pinnedFoldersObserver)
        }
    }

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.title = "フォルダー"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.style = .sourceList
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.setAccessibilityLabel("フォルダーツリー")
        outlineView.contextMenuProvider = { [weak self] event in
            self?.makeContextMenu(for: event)
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        reloadRoots()
    }

    func reloadRoots() {
        guard isViewLoaded else { return }
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let favoriteURLs: [URL] = [
            home,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
        // Protected folders must not be probed while merely constructing the sidebar.
        // Their contents are accessed only after an explicit user selection.
        let favorites = favoriteURLs.map { SidebarItem(url: $0) }

        let favoritePaths = Set(favorites.map { $0.url.standardizedFileURL.path })
        let volumes = directoryService.mountedVolumes()
            .filter { !favoritePaths.contains($0.standardizedFileURL.path) }
            .map { volume -> SidebarItem in
                let name = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? volume.lastPathComponent
                return SidebarItem(url: volume, title: name)
            }
        let pinnedItems = pinnedFoldersStore.urls.map {
            SidebarItem(url: $0, isPinned: true)
        }
        roots = [
            SidebarItem(sectionTitle: "クイックアクセス", children: pinnedItems),
            SidebarItem(sectionTitle: "場所", children: favorites + volumes)
        ]
        outlineView.reloadData()
        roots.forEach { outlineView.expandItem($0) }
    }

    private func loadChildren(for item: SidebarItem) {
        guard !item.isSection, !item.isLoading, !item.hasLoadedChildren else { return }
        item.isLoading = true
        directoryService.loadChildDirectories(of: item.url, showsHiddenFiles: showsHiddenFiles) { [weak self, weak item] urls in
            guard let self, let item else { return }
            item.children = urls.map { SidebarItem(url: $0) }
            item.isLoading = false
            item.hasLoadedChildren = true
            self.outlineView.reloadItem(item, reloadChildren: true)
        }
    }

    private func makeContextMenu(for event: NSEvent) -> NSMenu? {
        let location = outlineView.convert(event.locationInWindow, from: nil)
        let clickedRow = outlineView.row(at: location)
        guard clickedRow >= 0,
              let item = outlineView.item(atRow: clickedRow) as? SidebarItem,
              !item.isSection,
              !item.isPlaceholder else { return nil }

        let isPinned = pinnedFoldersStore.contains(item.url)
        let menu = NSMenu(title: "クイックアクセス")
        let menuItem = NSMenuItem(
            title: isPinned ? "クイックアクセスから外す" : "クイックアクセスにピン留め",
            action: #selector(togglePinnedFolder(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.representedObject = item.url
        menuItem.image = NSImage(
            systemSymbolName: isPinned ? "pin.slash" : "pin",
            accessibilityDescription: nil
        )
        menu.addItem(menuItem)
        return menu
    }

    @objc private func togglePinnedFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if pinnedFoldersStore.contains(url) {
            pinnedFoldersStore.unpin(url)
        } else {
            pinnedFoldersStore.pin(url)
        }
    }
}

extension FolderTreeViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? SidebarItem else { return roots.count }
        if item.isSection { return item.children.count }
        if !item.hasLoadedChildren {
            loadChildren(for: item)
            return 1
        }
        return item.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? SidebarItem else { return roots[index] }
        if item.isSection { return item.children[index] }
        if !item.hasLoadedChildren {
            return SidebarItem(url: item.url, title: "読み込み中…", isPlaceholder: true)
        }
        return item.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? SidebarItem else { return false }
        return item.isSection ? !item.children.isEmpty : !item.isPlaceholder
    }
}

extension FolderTreeViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarItem)?.isSection == true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier(item.isSection ? "FolderGroupCell" : "FolderCell")
        let cell: NSTableCellView

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let imageView = NSImageView()
            let textField = NSTextField(labelWithString: "")
            imageView.translatesAutoresizingMaskIntoConstraints = false
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            cell.imageView = imageView
            cell.textField = textField
            cell.addSubview(imageView)
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = item.title
        cell.textField?.textColor = item.isPlaceholder ? .secondaryLabelColor : .labelColor
        cell.textField?.font = item.isSection
            ? .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        cell.imageView?.isHidden = item.isSection
        if !item.isSection {
            cell.imageView?.image = item.isPlaceholder
                ? NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
                : item.isPinned
                    ? NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                    : NSWorkspace.shared.icon(forFile: item.url.path)
            cell.textField?.toolTip = item.url.path
        } else {
            cell.textField?.toolTip = nil
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let item = item as? SidebarItem else { return false }
        return !item.isSection && !item.isPlaceholder
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0,
              let item = outlineView.item(atRow: selectedRow) as? SidebarItem,
              !item.isSection,
              !item.isPlaceholder else { return }
        delegate?.folderTree(self, didSelect: item.url)
    }
}
