import AppKit
import Foundation

protocol BrowserViewControllerDelegate: AnyObject {
    func browser(_ browser: BrowserViewController, didRequestNavigateTo url: URL)
    func browser(_ browser: BrowserViewController, didRequestOpenInNewTab url: URL)
}

final class BrowserViewController: NSSplitViewController {
    weak var browserDelegate: BrowserViewControllerDelegate?

    private let folderTreeViewController: FolderTreeViewController
    private let fileListViewController: FileListViewController
    private let previewViewController = PreviewViewController()
    private(set) var currentURL: URL?
    private(set) var showsHiddenFiles = false
    private(set) var searchQuery = ""

    init(directoryService: DirectoryService) {
        folderTreeViewController = FolderTreeViewController(directoryService: directoryService)
        fileListViewController = FileListViewController(directoryService: directoryService)
        super.init(nibName: nil, bundle: nil)
        folderTreeViewController.delegate = self
        fileListViewController.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(sidebarWithViewController: folderTreeViewController)
        sidebar.minimumThickness = 170
        sidebar.maximumThickness = 360
        sidebar.canCollapse = true

        let content = NSSplitViewItem(viewController: fileListViewController)
        content.minimumThickness = 360

        let preview = NSSplitViewItem(viewController: previewViewController)
        preview.minimumThickness = 210
        preview.maximumThickness = 420
        preview.canCollapse = true

        addSplitViewItem(sidebar)
        addSplitViewItem(content)
        addSplitViewItem(preview)
    }

    func load(url: URL, showsHiddenFiles: Bool) {
        _ = view
        let normalizedURL = url.standardizedFileURL
        if currentURL != normalizedURL {
            searchQuery = ""
        }
        currentURL = normalizedURL
        self.showsHiddenFiles = showsHiddenFiles
        folderTreeViewController.showsHiddenFiles = showsHiddenFiles
        fileListViewController.load(
            directory: normalizedURL,
            showsHiddenFiles: showsHiddenFiles,
            searchQuery: searchQuery
        )
        previewViewController.show(item: nil)
    }

    func reload() {
        fileListViewController.reload()
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        fileListViewController.setSearchQuery(query)
    }

    func showQuickLook() {
        fileListViewController.showQuickLook()
    }
}

extension BrowserViewController: FolderTreeViewControllerDelegate {
    func folderTree(_ folderTree: FolderTreeViewController, didSelect url: URL) {
        browserDelegate?.browser(self, didRequestNavigateTo: url)
    }
}

extension BrowserViewController: FileListViewControllerDelegate {
    func fileList(_ fileList: FileListViewController, didRequestOpen item: FileItem) {
        if item.canBrowse {
            browserDelegate?.browser(self, didRequestNavigateTo: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func fileList(_ fileList: FileListViewController, didRequestOpenInNewTab url: URL) {
        browserDelegate?.browser(self, didRequestOpenInNewTab: url)
    }

    func fileList(_ fileList: FileListViewController, didSelect item: FileItem?) {
        previewViewController.show(item: item)
    }
}
