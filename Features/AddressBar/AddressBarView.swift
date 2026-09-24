import AppKit
import Foundation

private final class FolderSearchField: NSSearchField {
    var onTextChange: (() -> Void)?

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?()
    }
}

private final class BreadcrumbContainerView: NSView {
    var onBackgroundClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

private final class BreadcrumbButton: NSButton {
    let destinationURL: URL
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    init(title: String, destinationURL: URL, isCurrent: Bool, showsDriveIcon: Bool) {
        self.destinationURL = destinationURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        isBordered = false
        focusRingType = .none
        self.title = title
        font = .systemFont(ofSize: NSFont.systemFontSize, weight: isCurrent ? .semibold : .regular)
        lineBreakMode = .byTruncatingMiddle
        toolTip = destinationURL.path
        setAccessibilityLabel("\(title)へ移動")
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if showsDriveIcon {
            image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)
            imagePosition = .imageLeading
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        contentTintColor = .labelColor
    }
}

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidRequestBack(_ addressBar: AddressBarView)
    func addressBarDidRequestForward(_ addressBar: AddressBarView)
    func addressBarDidRequestUp(_ addressBar: AddressBarView)
    func addressBar(_ addressBar: AddressBarView, didSubmitPath path: String)
    func addressBar(_ addressBar: AddressBarView, didRequestNavigateTo url: URL)
    func addressBarDidRequestRefresh(_ addressBar: AddressBarView)
    func addressBarDidRequestOpenCurrentFolderInTerminal(_ addressBar: AddressBarView)
    func addressBar(_ addressBar: AddressBarView, didChangeHiddenFilesVisibility isVisible: Bool)
    func addressBar(_ addressBar: AddressBarView, didChangeSearchQuery query: String)
    func addressBarDidRequestFullDiskAccessSettings(_ addressBar: AddressBarView)
}

final class AddressBarView: NSView, NSTextFieldDelegate {
    weak var delegate: AddressBarViewDelegate?

    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private let refreshButton = NSButton()
    private let terminalButton = NSButton()
    private let settingsButton = NSButton()
    private let searchField = FolderSearchField()
    private let pathArea = NSView()
    private let breadcrumbContainer = BreadcrumbContainerView()
    private let breadcrumbStack = NSStackView()
    let pathField = NSTextField()
    private var showsHiddenFiles = false
    private var searchKeyMonitor: Any?
    private var currentPathURL = URL(fileURLWithPath: "/", isDirectory: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        if let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, searchKeyMonitor == nil {
            searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else { return event }
                if self.searchField.currentEditor() != nil {
                    self.searchTextChanged()
                }
                return event
            }
        } else if window == nil, let searchKeyMonitor {
            NSEvent.removeMonitor(searchKeyMonitor)
            self.searchKeyMonitor = nil
        }
    }

    func update(
        path: String,
        canGoBack: Bool,
        canGoForward: Bool,
        showsHiddenFiles: Bool,
        searchQuery: String
    ) {
        let pathURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if currentPathURL != pathURL {
            currentPathURL = pathURL
            rebuildBreadcrumbs()
        }
        if pathField.currentEditor() == nil {
            pathField.stringValue = path
        }
        if searchField.currentEditor() == nil {
            searchField.stringValue = searchQuery
        }
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        self.showsHiddenFiles = showsHiddenFiles

        let folderName = URL(fileURLWithPath: path).lastPathComponent
        searchField.placeholderString = folderName.isEmpty
            ? "このフォルダーを検索"
            : "\(folderName) を検索"
    }

    func focusPathField() {
        pathField.stringValue = currentPathURL.path
        breadcrumbContainer.isHidden = true
        pathField.isHidden = false
        window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    static func breadcrumbURLs(for url: URL) -> [URL] {
        let components = url.standardizedFileURL.pathComponents
        let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
        guard components.count > 1 else { return [rootURL] }

        var result = [rootURL]
        var currentURL = rootURL
        for component in components.dropFirst() where component != "/" {
            currentURL.appendPathComponent(component, isDirectory: true)
            result.append(currentURL.standardizedFileURL)
        }
        return result
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        configureSymbolButton(backButton, symbol: "chevron.left", label: "戻る", action: #selector(goBack))
        configureSymbolButton(forwardButton, symbol: "chevron.right", label: "進む", action: #selector(goForward))
        configureSymbolButton(upButton, symbol: "arrow.up", label: "上へ", action: #selector(goUp))
        configureSymbolButton(refreshButton, symbol: "arrow.clockwise", label: "更新", action: #selector(refresh))
        configureSymbolButton(
            terminalButton,
            symbol: "terminal",
            label: "現在のフォルダーをターミナルで開く",
            action: #selector(openCurrentFolderInTerminal)
        )

        pathField.placeholderString = "パスを入力"
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        pathField.delegate = self
        pathField.target = self
        pathField.action = #selector(submitPath)
        pathField.setAccessibilityLabel("現在のフォルダーのパス")
        pathField.isHidden = true

        pathArea.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbContainer.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbContainer.setAccessibilityLabel("現在のフォルダーの階層")
        breadcrumbContainer.onBackgroundClick = { [weak self] in self?.focusPathField() }
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbStack.orientation = .horizontal
        breadcrumbStack.alignment = .centerY
        breadcrumbStack.spacing = 0
        breadcrumbContainer.addSubview(breadcrumbStack)
        pathArea.addSubview(breadcrumbContainer)
        pathArea.addSubview(pathField)
        rebuildBreadcrumbs()

        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.setAccessibilityLabel("現在のフォルダーを検索")
        searchField.onTextChange = { [weak self] in self?.searchTextChanged() }

        configureSymbolButton(
            settingsButton,
            symbol: "gearshape",
            label: "表示設定",
            action: #selector(showSettings)
        )

        let navigationStack = NSStackView(views: [backButton, forwardButton, upButton])
        navigationStack.orientation = .horizontal
        navigationStack.spacing = 2

        let stack = NSStackView(
            views: [navigationStack, pathArea, refreshButton, terminalButton, searchField, settingsButton]
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathArea.heightAnchor.constraint(equalToConstant: 28),
            pathArea.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            breadcrumbContainer.leadingAnchor.constraint(equalTo: pathArea.leadingAnchor),
            breadcrumbContainer.trailingAnchor.constraint(equalTo: pathArea.trailingAnchor),
            breadcrumbContainer.topAnchor.constraint(equalTo: pathArea.topAnchor),
            breadcrumbContainer.bottomAnchor.constraint(equalTo: pathArea.bottomAnchor),
            breadcrumbStack.leadingAnchor.constraint(equalTo: breadcrumbContainer.leadingAnchor, constant: 4),
            breadcrumbStack.trailingAnchor.constraint(lessThanOrEqualTo: breadcrumbContainer.trailingAnchor, constant: -4),
            breadcrumbStack.centerYAnchor.constraint(equalTo: breadcrumbContainer.centerYAnchor),
            pathField.leadingAnchor.constraint(equalTo: pathArea.leadingAnchor),
            pathField.trailingAnchor.constraint(equalTo: pathArea.trailingAnchor),
            pathField.topAnchor.constraint(equalTo: pathArea.topAnchor),
            pathField.bottomAnchor.constraint(equalTo: pathArea.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            searchField.widthAnchor.constraint(equalToConstant: 240).withPriority(.defaultHigh)
        ])
    }

    private func configureSymbolButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    }

    private func rebuildBreadcrumbs() {
        for view in breadcrumbStack.arrangedSubviews {
            breadcrumbStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let urls = Self.breadcrumbURLs(for: currentPathURL)
        for (index, url) in urls.enumerated() {
            if index > 0 {
                let separator = NSImageView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                separator.contentTintColor = .tertiaryLabelColor
                separator.imageScaling = .scaleProportionallyDown
                separator.setAccessibilityElement(false)
                separator.setContentCompressionResistancePriority(.required, for: .horizontal)
                NSLayoutConstraint.activate([
                    separator.widthAnchor.constraint(equalToConstant: 12),
                    separator.heightAnchor.constraint(equalToConstant: 12)
                ])
                breadcrumbStack.addArrangedSubview(separator)
            }

            let title: String
            if url.path == "/" {
                title = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                    ?? FileManager.default.displayName(atPath: "/")
            } else {
                title = url.lastPathComponent
            }
            let button = BreadcrumbButton(
                title: title,
                destinationURL: url,
                isCurrent: index == urls.count - 1,
                showsDriveIcon: index == 0
            )
            button.target = self
            button.action = #selector(navigateToBreadcrumb(_:))
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            breadcrumbStack.addArrangedSubview(button)
        }
    }

    private func finishEditingPath() {
        pathField.isHidden = true
        breadcrumbContainer.isHidden = false
    }

    @objc private func goBack() {
        delegate?.addressBarDidRequestBack(self)
    }

    @objc private func goForward() {
        delegate?.addressBarDidRequestForward(self)
    }

    @objc private func goUp() {
        delegate?.addressBarDidRequestUp(self)
    }

    @objc private func submitPath() {
        let submittedPath = pathField.stringValue
        finishEditingPath()
        window?.makeFirstResponder(nil)
        delegate?.addressBar(self, didSubmitPath: submittedPath)
    }

    @objc private func navigateToBreadcrumb(_ sender: BreadcrumbButton) {
        guard sender.destinationURL != currentPathURL else { return }
        delegate?.addressBar(self, didRequestNavigateTo: sender.destinationURL)
    }

    @objc private func refresh() {
        delegate?.addressBarDidRequestRefresh(self)
    }

    @objc private func openCurrentFolderInTerminal() {
        delegate?.addressBarDidRequestOpenCurrentFolderInTerminal(self)
    }

    @objc private func searchTextChanged() {
        delegate?.addressBar(self, didChangeSearchQuery: searchField.stringValue)
    }

    @objc private func showSettings(_ sender: NSButton) {
        let menu = NSMenu(title: "表示設定")

        let hiddenFilesItem = NSMenuItem(
            title: "隠しファイルを表示",
            action: #selector(toggleHiddenFiles),
            keyEquivalent: ""
        )
        hiddenFilesItem.target = self
        hiddenFilesItem.state = showsHiddenFiles ? .on : .off
        hiddenFilesItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        menu.addItem(hiddenFilesItem)
        menu.addItem(.separator())

        let fullDiskAccessItem = NSMenuItem(
            title: "フルディスクアクセス設定を開く…",
            action: #selector(openFullDiskAccessSettings),
            keyEquivalent: ""
        )
        fullDiskAccessItem.target = self
        fullDiskAccessItem.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        menu.addItem(fullDiskAccessItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    }

    @objc private func toggleHiddenFiles() {
        showsHiddenFiles.toggle()
        delegate?.addressBar(self, didChangeHiddenFilesVisibility: showsHiddenFiles)
    }

    @objc private func openFullDiskAccessSettings() {
        delegate?.addressBarDidRequestFullDiskAccessSettings(self)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField, textField === pathField else { return }
        finishEditingPath()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === pathField,
              commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
            return false
        }
        pathField.stringValue = currentPathURL.path
        window?.makeFirstResponder(nil)
        finishEditingPath()
        return true
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
