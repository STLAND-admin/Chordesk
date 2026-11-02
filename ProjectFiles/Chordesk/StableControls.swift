import Foundation

enum ControlRailPosition {
    static func fraction(_ value: Double, maximum: Double) -> Double {
        value.isFinite ? min(max(value, 0), maximum) : 0
    }
    static func trailingInset(containerWidth: CGFloat, anchorX: CGFloat?, buttonWidth: CGFloat) -> CGFloat {
        guard let anchorX, anchorX.isFinite else { return 0 }
        return max(0, containerWidth - anchorX - buttonWidth / 2)
    }
}

enum RearStatusPlacement {
    /// Choose the highest free trailing position using public reserved regions.
    static func frame(size: CGSize, in bounds: CGRect, avoiding regions: [CGRect]) -> CGRect {
        let size = CGSize(width: min(max(0, size.width), bounds.width), height: max(0, size.height))
        let rows = ([bounds.minY] + regions.map(\.maxY)).sorted()
        for y in rows where y >= bounds.minY && y + size.height <= bounds.maxY {
            var candidate = CGRect(x: bounds.maxX - size.width, y: y, width: size.width, height: size.height)
            for obstacle in regions.sorted(by: { $0.maxX > $1.maxX }) where candidate.intersects(obstacle) {
                candidate.origin.x = obstacle.minX - size.width
            }
            if candidate.minX >= bounds.minX && !regions.contains(where: { $0.intersects(candidate) }) { return candidate }
        }
        return CGRect(origin: bounds.origin, size: size)
    }
}

/// Hold a menu's snapshot and selected action until its dismissal completes.
struct MenuInteractionState {
    private(set) var presented = false
    private var selected: String?
    mutating func begin() { presented = true; selected = nil }
    mutating func select(_ id: String) -> String? {
        if presented { if selected == nil { selected = id }; return nil }
        return id
    }
    mutating func end() -> String? {
        presented = false
        defer { selected = nil }
        return selected
    }
}

#if os(iOS)
import SwiftUI
import UIKit

struct RearStatusPositionReader: UIViewRepresentable {
    var size: CGSize
    var onChange: (CGRect) -> Void
    func makeUIView(context: Context) -> RearStatusPositionView { RearStatusPositionView() }
    func updateUIView(_ view: RearStatusPositionView, context: Context) {
        view.badgeSize = size; view.onChange = onChange; view.setNeedsLayout()
    }
}

final class RearStatusPositionView: UIView {
    var badgeSize = CGSize.zero
    var onChange: ((CGRect) -> Void)?
    private var previous = CGRect.null
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window, badgeSize.width > 0 else { return }
        let usable: CGRect
        let obstacles: [CGRect]
        if #available(iOS 27.1, *) {
            usable = bounds
            obstacles = window.reservedRegions(kind: .occlusion).filter(\.isActive).map {
                convert($0.frame, from: window)
            }
        } else {
            usable = convert(window.bounds.inset(by: window.safeAreaInsets), from: window)
            obstacles = []
        }
        let result = RearStatusPlacement.frame(size: badgeSize, in: usable, avoiding: obstacles)
        guard result != previous else { return }
        previous = result
        DispatchQueue.main.async { [weak self] in self?.onChange?(result) }
    }
}

/// Read the public bar layout region so an edge Dock avoids system ornaments.
/// Its extent comes from the actual controls, never a device/model threshold.
struct SystemStatusBoundaryReader: UIViewRepresentable {
    var extent: CGFloat
    var onChange: (CGFloat, CGFloat, CGFloat?) -> Void
    func makeUIView(context: Context) -> StatusBoundaryView { StatusBoundaryView() }
    func updateUIView(_ view: StatusBoundaryView, context: Context) {
        view.onChange = onChange; view.extent = extent
        view.setNeedsLayout()
    }
}

final class StatusBoundaryView: UIView {
    var onChange: ((CGFloat, CGFloat, CGFloat?) -> Void)?
    var extent: CGFloat = 0
    private var last = CGPoint(x: -1, y: -1)
    private var lastAnchor: CGFloat?
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window, extent > 0 else { return }
        let inset: UIEdgeInsets
        var anchor: CGFloat?
        if #available(iOS 27.1, *) {
            inset = window.edgeInsets(for: .bar(onEdge: NSDirectionalRectEdge.trailing, extent: extent))
            // Align beneath the system's upper trailing occlusion, not a private
            // Wi-Fi subview or a guessed model-specific screen coordinate.
            if let region = window.reservedRegions(kind: .occlusion)
                .filter({ $0.isActive && $0.frame.midX > window.bounds.midX && $0.frame.midY < window.bounds.midY })
                .max(by: { $0.frame.maxX < $1.frame.maxX }) {
                anchor = convert(region.frame.inset(by: region.margins), from: window).midX
            }
        } else { inset = window.safeAreaInsets }
        let safe = convert(window.bounds.inset(by: inset), from: window)
        let top = max(0, safe.minY), bottom = max(0, bounds.maxY - safe.maxY)
        guard top.isFinite, bottom.isFinite,
              abs(top - last.x) > 0.5 || abs(bottom - last.y) > 0.5 || anchor != lastAnchor else { return }
        last = CGPoint(x: top, y: bottom)
        lastAnchor = anchor
        DispatchQueue.main.async { [weak self] in self?.onChange?(top, bottom, anchor) }
    }
}

struct SystemMenuItem: Equatable {
    var id: String
    var title: String
    var symbol: String = ""
    var selected = false
    var enabled = true
    var destructive = false
}
struct SystemMenuSection: Equatable {
    var title = ""
    var submenu = false
    var items: [SystemMenuItem]
}

/// A native popover with ordinary table rows avoids context-menu press tracking.
/// The presented list owns an immutable snapshot while the desktop keeps updating.
struct StableMenuButton: UIViewControllerRepresentable {
    var symbol: String
    var title: String
    var identifier: String
    var sections: [SystemMenuSection]
    var primaryAction: (() -> Void)? = nil
    var onPresentation: (Bool) -> Void
    var onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> StableMenuController { StableMenuController() }
    func updateUIViewController(_ controller: StableMenuController, context: Context) {
        controller.configure(symbol: symbol, title: title, identifier: identifier, sections: sections,
                             primaryAction: primaryAction, onPresentation: onPresentation, onSelect: onSelect)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: StableMenuController, context: Context) -> CGSize? {
        let side = uiViewController.buttonDiameter
        return CGSize(width: side, height: side)
    }
    static func dismantleUIViewController(_ controller: StableMenuController, coordinator: ()) { controller.cancelMenu() }
}

final class StableMenuController: UIViewController, UIPopoverPresentationControllerDelegate {
    let button = UIButton(type: .system)
    private(set) var buttonDiameter: CGFloat = 0
    private var menuState = MenuInteractionState()
    private var latest: [SystemMenuSection] = []
    private var primary: (() -> Void)?
    private var presentation: ((Bool) -> Void)?
    private var selection: ((String) -> Void)?
    private var configuredSymbol = ""
    private var menuTitle = ""
    private var panel: UINavigationController?
    private var inactiveObserver: NSObjectProtocol?
    private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))

    override func loadView() { view = button }
    override func viewDidLoad() {
        super.viewDidLoad()
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        hold.cancelsTouchesInView = true
        button.addGestureRecognizer(hold)
        inactiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancelMenu() }
            }
    }
    func configure(symbol: String, title: String, identifier: String, sections: [SystemMenuSection],
                   primaryAction: (() -> Void)?, onPresentation: @escaping (Bool) -> Void,
                   onSelect: @escaping (String) -> Void) {
        loadViewIfNeeded()
        latest = sections; primary = primaryAction; presentation = onPresentation; selection = onSelect
        menuTitle = title
        button.accessibilityIdentifier = identifier; button.accessibilityLabel = title
        let usesHold = primaryAction != nil && !sections.isEmpty
        if hold.isEnabled != usesHold { hold.isEnabled = usesHold }
        // A showing popover is never rebuilt by a video frame or rear-contact update.
        guard !menuState.presented else { return }
        if configuredSymbol != symbol {
            configuredSymbol = symbol
            var config = UIButton.Configuration.plain()
            let symbols = UIImage.SymbolConfiguration(font: .preferredFont(forTextStyle: .title3))
            let image = UIImage(systemName: symbol, withConfiguration: symbols)
            let glyphWidth = ["slider.horizontal.3", "keyboard", "keyboard.chevron.compact.down"]
                .compactMap { UIImage(systemName: $0, withConfiguration: symbols)?.size.width }.max() ?? 0
            let glyphHeight = ["slider.horizontal.3", "keyboard", "keyboard.chevron.compact.down"]
                .compactMap { UIImage(systemName: $0, withConfiguration: symbols)?.size.height }.max() ?? 0
            let diameter = max(glyphWidth, glyphHeight) + 28
            buttonDiameter = ceil(diameter)
            let sidePadding = max(0, diameter - (image?.size.width ?? 0)) / 2
            let verticalPadding = max(0, diameter - (image?.size.height ?? 0)) / 2
            config.baseForegroundColor = .secondaryLabel
            config.image = image
            config.contentInsets = NSDirectionalEdgeInsets(top: verticalPadding, leading: sidePadding, bottom: verticalPadding, trailing: sidePadding)
            button.configuration = config
            button.invalidateIntrinsicContentSize()
        }
    }
    @objc private func tapped() {
        guard !menuState.presented else { return }
        if let primary { primary() } else { openMenu() }
    }
    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { openMenu() }
    }
    private func openMenu() {
        guard panel == nil, presentedViewController == nil, let window = button.window else { return }
        let list = MenuActionList(title: menuTitle, sections: latest, onSelect: { [weak self] id in
            guard let self, self.menuState.presented else { return }
            _ = self.menuState.select(id)
            self.closeMenu()
        }, onCancel: { [weak self] in self?.cancelMenu() })
        let navigation = MenuGlassNavigationController(rootViewController: list)
        navigation.modalPresentationStyle = .popover
        navigation.applyGlassPresentation()
        let available = window.safeAreaLayoutGuide.layoutFrame.size
        navigation.preferredContentSize = CGSize(width: available.width * 0.72, height: available.height * 0.72)
        if let popover = navigation.popoverPresentationController {
            popover.sourceView = button
            popover.sourceRect = button.bounds
            popover.delegate = self
            // Tapping outside only dismisses; it must not click the remote desktop.
            popover.passthroughViews = nil
        }
        panel = navigation; menuState.begin(); presentation?(true)
        present(navigation, animated: true)
    }
    private func closeMenu() {
        guard let panel else { return }
        panel.dismiss(animated: true) { [weak self, weak panel] in
            guard let panel else { return }; self?.finish(panel)
        }
    }
    private func finish(_ dismissed: UIViewController) {
        guard panel === dismissed else { return }
        panel = nil
        let selected = menuState.end()
        presentation?(false)
        // Open sheets and send commands only after the popover releases input.
        if let selected { selection?(selected) }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(presentationController.presentedViewController)
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        finish(popoverPresentationController.presentedViewController)
    }
    func cancelMenu() {
        guard menuState.presented else { return }
        menuState.begin() // Discard an uncommitted selection on cancellation/backgrounding.
        closeMenu()
    }
    deinit { if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) } }
}

/// Visual material is independent of selection. Glass never owns touch gestures.
private final class MenuGlassNavigationController: UINavigationController {
    func applyGlassPresentation() {
        if #available(iOS 26.1, *), !UIAccessibility.isReduceTransparencyEnabled {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            presentationController?.backgroundEffect = effect
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Reapply to the system presentation after popover-to-sheet adaptation.
        applyGlassPresentation()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

/// Standard UIKit list selection handles a short tap without a long-press recognizer.
private final class MenuActionList: UITableViewController {
    private let sections: [SystemMenuSection]
    private let onSelect: (String) -> Void
    private let onCancel: () -> Void
    init(title: String, sections: [SystemMenuSection], onSelect: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.sections = sections; self.onSelect = onSelect; self.onCancel = onCancel
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "remote-action-list"
        tableView.delaysContentTouches = false
        tableView.backgroundColor = .clear
        let backdrop: UIView
        if #available(iOS 26.1, *), !UIAccessibility.isReduceTransparencyEnabled {
            // The system presentation supplies the material; do not stack glass
            // on top of its opaque default sheet background.
            backdrop = UIView()
            backdrop.backgroundColor = .clear
        } else if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            backdrop = UIVisualEffectView(effect: effect)
        } else {
            backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            if UIAccessibility.isReduceTransparencyEnabled { backdrop.backgroundColor = .secondarySystemBackground }
        }
        backdrop.isUserInteractionEnabled = false
        tableView.backgroundView = backdrop
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(done))
    }
    @objc private func done() { onCancel() }
    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].submenu ? 1 : sections[section].items.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let value = sections[section]
        return value.submenu || value.title.isEmpty ? nil : value.title
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let item = section.submenu ? SystemMenuItem(id: "submenu-" + section.title, title: section.title) : section.items[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.image = item.symbol.isEmpty ? nil : UIImage(systemName: item.symbol)
        content.textProperties.color = !item.enabled ? .secondaryLabel : item.destructive ? .systemRed : .label
        content.imageProperties.tintColor = .secondaryLabel
        cell.tintColor = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessoryType = section.submenu ? .disclosureIndicator : item.selected ? .checkmark : .none
        cell.selectionStyle = item.enabled ? .default : .none
        cell.isAccessibilityElement = true
        cell.accessibilityIdentifier = item.id
        cell.accessibilityLabel = item.title
        cell.accessibilityTraits = item.enabled ? [.button] : [.button, .notEnabled]
        cell.accessibilityValue = item.selected ? "已选中" : nil
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = sections[indexPath.section]
        if section.submenu {
            navigationController?.pushViewController(MenuActionList(title: section.title,
                sections: [.init(items: section.items)], onSelect: onSelect, onCancel: onCancel), animated: true)
        } else if section.items[indexPath.row].enabled { onSelect(section.items[indexPath.row].id) }
    }
}
#endif
