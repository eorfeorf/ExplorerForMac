import AppKit
import Foundation

private final class WindowActionButton: NSButton {
    enum Kind {
        case minimize
        case maximize
        case close

        var symbolName: String {
            switch self {
            case .minimize: return "minus"
            case .maximize: return "square"
            case .close: return "xmark"
            }
        }

        var isDestructive: Bool { self == .close }
    }

    private let kind: Kind
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    init(kind: Kind, label: String, target: AnyObject?, action: Selector) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: label)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        self.target = target
        self.action = action
        toolTip = label
        setAccessibilityLabel(label)
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
        let backgroundColor: NSColor
        if isHovering {
            backgroundColor = kind.isDestructive
                ? .systemRed
                : NSColor.labelColor.withAlphaComponent(0.12)
        } else {
            backgroundColor = .clear
        }
        layer?.backgroundColor = backgroundColor.cgColor
        contentTintColor = isHovering && kind.isDestructive ? .white : .secondaryLabelColor
    }
}

protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelect index: Int)
    func tabBar(_ tabBar: TabBarView, didRequestDetach index: Int, at screenPoint: NSPoint?)
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
    func tabBarDidRequestCloseCurrentTab(_ tabBar: TabBarView)
}

final class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?

    override var mouseDownCanMoveWindow: Bool { true }

    private let tabControl = NSSegmentedControl()
    private let addButton = NSButton()
    private let detachTabButton = NSButton()
    private let closeTabButton = NSButton()
    private lazy var tabDragRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handleTabDrag(_:)))
    private var draggedTabIndex: Int?

    private lazy var minimizeWindowButton = WindowActionButton(
        kind: .minimize,
        label: "ウインドウをしまう",
        target: self,
        action: #selector(minimizeWindow)
    )
    private lazy var maximizeWindowButton = WindowActionButton(
        kind: .maximize,
        label: "最大化／元に戻す",
        target: self,
        action: #selector(maximizeWindow)
    )
    private lazy var closeWindowButton = WindowActionButton(
        kind: .close,
        label: "ウインドウを閉じる",
        target: self,
        action: #selector(closeWindow)
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    func update(titles: [String], selectedIndex: Int) {
        tabControl.segmentCount = titles.count
        for (index, title) in titles.enumerated() {
            tabControl.setLabel(title, forSegment: index)
            tabControl.setWidth(min(190, max(90, CGFloat(title.count * 9 + 34))), forSegment: index)
            tabControl.setToolTip(title, forSegment: index)
        }
        if titles.indices.contains(selectedIndex) {
            tabControl.selectedSegment = selectedIndex
        }
        closeTabButton.isEnabled = !titles.isEmpty
        detachTabButton.isEnabled = titles.count > 1
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        tabControl.segmentStyle = .rounded
        tabControl.trackingMode = .selectOne
        tabControl.target = self
        tabControl.action = #selector(selectTab)
        tabControl.setAccessibilityLabel("タブ")
        tabControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabControl.addGestureRecognizer(tabDragRecognizer)

        configureButton(addButton, symbol: "plus", label: "新規タブ", action: #selector(addTab))
        configureButton(
            detachTabButton,
            symbol: "macwindow.on.rectangle",
            label: "現在のタブを新しいウインドウへ移動",
            action: #selector(detachTab)
        )
        configureButton(closeTabButton, symbol: "xmark.circle", label: "現在のタブを閉じる", action: #selector(closeTab))

        let tabStack = NSStackView(views: [tabControl, addButton, detachTabButton, closeTabButton])
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 6

        let windowControlContainer = NSView()
        windowControlContainer.translatesAutoresizingMaskIntoConstraints = false
        windowControlContainer.addSubview(minimizeWindowButton)
        windowControlContainer.addSubview(maximizeWindowButton)
        windowControlContainer.addSubview(closeWindowButton)

        addSubview(tabStack)
        addSubview(windowControlContainer)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            tabStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: windowControlContainer.leadingAnchor, constant: -10),
            tabStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            windowControlContainer.topAnchor.constraint(equalTo: topAnchor),
            windowControlContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            windowControlContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            windowControlContainer.widthAnchor.constraint(equalToConstant: 138),
            minimizeWindowButton.leadingAnchor.constraint(equalTo: windowControlContainer.leadingAnchor),
            minimizeWindowButton.topAnchor.constraint(equalTo: windowControlContainer.topAnchor),
            minimizeWindowButton.bottomAnchor.constraint(equalTo: windowControlContainer.bottomAnchor),
            minimizeWindowButton.widthAnchor.constraint(equalToConstant: 46),
            minimizeWindowButton.heightAnchor.constraint(equalToConstant: 38),
            maximizeWindowButton.leadingAnchor.constraint(equalTo: minimizeWindowButton.trailingAnchor),
            maximizeWindowButton.topAnchor.constraint(equalTo: windowControlContainer.topAnchor),
            maximizeWindowButton.bottomAnchor.constraint(equalTo: windowControlContainer.bottomAnchor),
            maximizeWindowButton.widthAnchor.constraint(equalToConstant: 46),
            maximizeWindowButton.heightAnchor.constraint(equalToConstant: 38),
            closeWindowButton.leadingAnchor.constraint(equalTo: maximizeWindowButton.trailingAnchor),
            closeWindowButton.topAnchor.constraint(equalTo: windowControlContainer.topAnchor),
            closeWindowButton.bottomAnchor.constraint(equalTo: windowControlContainer.bottomAnchor),
            closeWindowButton.trailingAnchor.constraint(equalTo: windowControlContainer.trailingAnchor),
            closeWindowButton.widthAnchor.constraint(equalToConstant: 46),
            closeWindowButton.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func configureButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    @objc private func selectTab() {
        guard tabControl.selectedSegment >= 0 else { return }
        delegate?.tabBar(self, didSelect: tabControl.selectedSegment)
    }

    @objc private func addTab() {
        delegate?.tabBarDidRequestNewTab(self)
    }

    @objc private func detachTab() {
        guard tabControl.selectedSegment >= 0 else { return }
        delegate?.tabBar(self, didRequestDetach: tabControl.selectedSegment, at: nil)
    }

    @objc private func closeTab() {
        delegate?.tabBarDidRequestCloseCurrentTab(self)
    }

    @objc private func handleTabDrag(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let point = recognizer.location(in: tabControl)
            guard let index = tabIndex(at: point) else {
                draggedTabIndex = nil
                return
            }
            draggedTabIndex = index
            tabControl.selectedSegment = index
            tabControl.alphaValue = 0.7
            delegate?.tabBar(self, didSelect: index)
        case .ended:
            defer {
                draggedTabIndex = nil
                tabControl.alphaValue = 1
            }
            guard let index = draggedTabIndex else { return }
            let point = recognizer.location(in: self)
            let translation = recognizer.translation(in: self)
            let movedFarEnough = hypot(translation.x, translation.y) >= 20
            let endedOutsideTabBar = !bounds.insetBy(dx: -12, dy: -12).contains(point)
            guard movedFarEnough, endedOutsideTabBar else { return }
            let windowPoint = recognizer.location(in: nil)
            let screenPoint = window?.convertPoint(toScreen: windowPoint)
            delegate?.tabBar(self, didRequestDetach: index, at: screenPoint)
        case .cancelled, .failed:
            draggedTabIndex = nil
            tabControl.alphaValue = 1
        default:
            break
        }
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        guard tabControl.bounds.contains(point), tabControl.segmentCount > 0 else { return nil }
        var leadingEdge: CGFloat = 0
        for index in 0..<tabControl.segmentCount {
            let trailingEdge = leadingEdge + tabControl.width(forSegment: index)
            if point.x >= leadingEdge, point.x <= trailingEdge {
                return index
            }
            leadingEdge = trailingEdge
        }
        return nil
    }

    @objc private func minimizeWindow() {
        window?.miniaturize(nil)
    }

    @objc private func maximizeWindow() {
        window?.performZoom(nil)
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }
}
