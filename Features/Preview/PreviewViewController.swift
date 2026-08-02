import AppKit

final class PreviewViewController: NSViewController {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(wrappingLabelWithString: "項目を選択してください")
    private let kindLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "開く", target: nil, action: nil)
    private let revealButton = NSButton(title: "Finderで表示", target: nil, action: nil)
    private var item: FileItem?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.alignment = .center
        kindLabel.textColor = .secondaryLabelColor
        kindLabel.alignment = .center
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        detailsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        openButton.target = self
        openButton.action = #selector(openItem)
        revealButton.target = self
        revealButton.action = #selector(revealItem)
        openButton.isHidden = true
        revealButton.isHidden = true

        let buttons = NSStackView(views: [openButton, revealButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let stack = NSStackView(views: [iconView, nameLabel, kindLabel, pathLabel, detailsLabel, buttons])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: pathLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            kindLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pathLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    func show(item: FileItem?) {
        self.item = item
        guard let item else {
            iconView.image = nil
            nameLabel.stringValue = "項目を選択してください"
            kindLabel.stringValue = ""
            pathLabel.stringValue = ""
            detailsLabel.stringValue = ""
            openButton.isHidden = true
            revealButton.isHidden = true
            return
        }

        iconView.image = NSWorkspace.shared.icon(forFile: item.url.path)
        nameLabel.stringValue = item.name
        kindLabel.stringValue = item.kind
        pathLabel.stringValue = item.url.path
        pathLabel.toolTip = item.url.path

        var details: [String] = []
        if let modifiedAt = item.modifiedAt {
            details.append("更新日時: \(dateFormatter.string(from: modifiedAt))")
        }
        if let size = item.size {
            details.append("サイズ: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        }
        if item.isSymbolicLink {
            details.append("シンボリックリンク")
        }
        detailsLabel.stringValue = details.joined(separator: "\n")
        openButton.isHidden = false
        revealButton.isHidden = false
    }

    @objc private func openItem() {
        guard let item else { return }
        NSWorkspace.shared.open(item.url)
    }

    @objc private func revealItem() {
        guard let item else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
