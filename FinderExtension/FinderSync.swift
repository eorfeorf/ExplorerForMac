import AppKit
import FinderSync
import Foundation

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override var toolbarItemName: String {
        "Explorer for Mac"
    }

    override var toolbarItemToolTip: String {
        "現在のフォルダーをExplorer for Macで開く"
    }

    override var toolbarItemImage: NSImage {
        let image = NSImage(
            systemSymbolName: "folder.badge.plus",
            accessibilityDescription: toolbarItemToolTip
        ) ?? NSImage(named: NSImage.folderName)!
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Explorer for Mac")
        let item = NSMenuItem(
            title: "このフォルダーをExplorer for Macで開く",
            action: #selector(openCurrentFolder(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
        item.isEnabled = currentFolderURL() != nil
        menu.addItem(item)
        return menu
    }

    @objc private func openCurrentFolder(_ sender: Any?) {
        guard let folderURL = currentFolderURL(),
              let applicationURL = containingApplicationURL() else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    private func currentFolderURL() -> URL? {
        guard var url = FIFinderSyncController.default().targetedURL()?.standardizedFileURL else {
            return nil
        }
        if let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
           isDirectory == false {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func containingApplicationURL() -> URL? {
        guard let executablePath = Foundation.ProcessInfo.processInfo.arguments.first else {
            return nil
        }
        var url = URL(fileURLWithPath: executablePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        guard url.pathExtension == "app" else { return nil }
        return url
    }
}
