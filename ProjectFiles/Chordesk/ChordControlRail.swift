#if os(iOS)
import SwiftUI
import UIKit

/// UIKit owns all glass, segment tracking and button presses. The transparent
/// hosting view only intercepts the rail itself, leaving the remote canvas live.
struct ChordControlRail: UIViewControllerRepresentable {
    var mode: FrontTouchMode
    var showMode: Bool
    var showDisplay: Bool
    var showOverview: Bool
    var keyboardShown: Bool
    var modifiers: UInt
    var inputAllowed: Bool
    var visible: Bool
    var keyboardTop: CGFloat?
    var statusBottom: CGFloat
    var topOffset: Double
    var bottomOffset: Double
    var menuSections: [SystemMenuSection]
    var keyboardSections: [SystemMenuSection]
    var onMode: (FrontTouchMode) -> Void
    var onKeyboard: () -> Void
    var onModifier: (UInt) -> Void
    var onDisplay: () -> Void
    var onOverview: (WindowOverviewAction) -> Void
    var onPresentation: (Bool) -> Void
    var onMenu: (String) -> Void
    var onKeyboardMenu: (String) -> Void
    var onGeometry: (CGRect, CGFloat) -> Void

    func makeUIViewController(context: Context) -> ChordRailController { ChordRailController() }
    func updateUIViewController(_ controller: ChordRailController, context: Context) { controller.configure(self) }
    static func dismantleUIViewController(_ controller: ChordRailController, coordinator: ()) { controller.cancelMenus() }
}

private final class RailHitView: UIView {
    var targets: [UIView] = []
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        for target in targets.reversed() where !target.isHidden && target.alpha > 0.01 {
            let local = target.convert(point, from: self)
            if target.point(inside: local, with: event), let hit = target.hitTest(local, with: event) { return hit }
        }
        return nil
    }
}

/// A padded, clipped viewport leaves room for Apple's elastic glass while
/// still culling offscreen controls. Its padding does not steal canvas touches.
private final class RailGlassScrollView: UIScrollView {
    var glassOutset: CGFloat = 0
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: glassOutset, dy: 0).contains(point)
    }
}

/// A vertical arrangement of Apple's segmented control. The system supplies the
/// elastic selection lens; rotating symbol artwork merely keeps symbols upright.
private final class PointerModeSegments: UIVisualEffectView {
    let control: UISegmentedControl
    var onChange: ((FrontTouchMode) -> Void)?
    private var symbolExtent: CGFloat = 0
    private let options = [("直接触控", "hand.point.up.left"), ("触控板", "cursorarrow.motionlines")]
    init() {
        control = UISegmentedControl(items: ["", ""])
        super.init(effect: nil)
        insetsLayoutMarginsFromSafeArea = false
        contentView.insetsLayoutMarginsFromSafeArea = false
        clipsToBounds = false
        if #available(iOS 26.0, *) { cornerConfiguration = .capsule() }
        updateMaterial()
        control.accessibilityIdentifier = "pointer-mode-toggle"
        control.accessibilityLabel = "操控模式"
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(changed), for: .valueChanged)
        control.tintColor = RailSymbol.foreground
        control.selectedSegmentTintColor = RailSymbol.foreground
        control.setTitleTextAttributes([.foregroundColor: RailSymbol.foreground], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        if #available(iOS 26.0, *) { control.cornerConfiguration = .capsule() }
        control.layer.cornerCurve = .circular
        let extent = control.intrinsicContentSize.height * 1.5
        for index in options.indices { control.setWidth(extent, forSegmentAt: index) }
        refreshSymbols()
        contentView.addSubview(control)
    }
    func updateMaterial() {
        if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
            // The segmented control retains its native thumb. A clear outer
            // interactive glass supplies whole-capsule press/drag feedback
            // without stacking a second regular blur behind that control.
            let glass = UIGlassEffect(style: .clear)
            glass.isInteractive = true
            glass.tintColor = UIColor.systemGray.withAlphaComponent(0.12)
            effect = glass
            backgroundColor = .clear
        } else {
            effect = nil
            backgroundColor = .secondarySystemBackground
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        let size = control.intrinsicContentSize
        return CGSize(width: size.height, height: size.width)
    }
    func refreshSymbols() {
        guard symbolExtent != RailSymbol.extent, !control.isTracking else { return }
        symbolExtent = RailSymbol.extent
        let selected = control.selectedSegmentIndex
        for (index, pair) in options.enumerated() {
            control.setAction(UIAction(title: pair.0, image: RailSymbol.image(pair.1, rotated: true)) { _ in }, forSegmentAt: index)
        }
        control.selectedSegmentIndex = selected
    }
    func select(_ mode: FrontTouchMode) {
        // Video frames must not interrupt the native thumb's press/drag tracking.
        guard !control.isTracking else { return }
        control.selectedSegmentIndex = mode == .direct ? 0 : 1
        control.accessibilityValue = mode.title
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        control.transform = .identity
        control.bounds = CGRect(origin: .zero, size: CGSize(width: bounds.height, height: bounds.width))
        control.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        control.transform = CGAffineTransform(rotationAngle: -.pi / 2)
    }
    @objc private func changed() { onChange?(control.selectedSegmentIndex == 0 ? .direct : .trackpad) }
}

final class ChordRailController: UIViewController {
    private var configuration: ChordControlRail?
    private let root = RailHitView()
    private let scroll = RailGlassScrollView()
    private let stack = UIStackView()
    private let actionsGlass = UIVisualEffectView()
    private let mode = PointerModeSegments()
    private let menu = StableMenuController()
    private let display = StableMenuController()
    private let overview = StableMenuController()
    private let keyboard = StableMenuController()
    private let modifierContainer = UIVisualEffectView()
    private let modifierStack = UIStackView()
    private var modifierButtons: [UInt: UIButton] = [:]
    private var lastGeometry = CGRect.null
    private var lastAnchor: CGFloat?
    private var observers: [NSObjectProtocol] = []

    override func loadView() { view = root }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.insetsLayoutMarginsFromSafeArea = false
        view.backgroundColor = .clear; view.tintColor = .label
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false; scroll.delaysContentTouches = false
        scroll.insetsLayoutMarginsFromSafeArea = false
        // Keep clipping for offscreen shortcuts, but pad the viewport around
        // their resting frames so native elastic glass has room to expand.
        scroll.clipsToBounds = true
        view.clipsToBounds = false
        view.addSubview(scroll); scroll.addSubview(actionsGlass); scroll.addSubview(mode)
        if #available(iOS 26.0, *) { actionsGlass.cornerConfiguration = .capsule() }
        actionsGlass.layer.cornerCurve = .circular
        actionsGlass.contentView.addSubview(stack)
        for container in [stack, actionsGlass.contentView, modifierContainer.contentView, modifierStack] {
            container.insetsLayoutMarginsFromSafeArea = false
        }
        stack.axis = .vertical; stack.distribution = .fillEqually
        for child in [menu, display, overview, keyboard] {
            addChild(child); child.loadViewIfNeeded()
            if child === keyboard { view.addSubview(child.view) } else { stack.addArrangedSubview(child.view) }
            child.didMove(toParent: self)
        }
        mode.onChange = { [weak self] in self?.configuration?.onMode($0) }
        modifierContainer.contentView.addSubview(modifierStack)
        modifierStack.axis = .horizontal; modifierStack.spacing = 4; modifierStack.distribution = .fillEqually
        view.addSubview(modifierContainer)
        for (flag, title, symbol) in [(UInt(8), "Ctrl", "control"), (UInt(4), "Option", "option"), (UInt(2), "Command", "command")] {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "native-modifier-\(flag)"
            button.accessibilityLabel = title
            var config: UIButton.Configuration
            if #available(iOS 26.0, *) { config = .glass() } else { config = .bordered() }
            config.image = UIImage(systemName: symbol); config.buttonSize = .large
            config.cornerStyle = .capsule; config.baseForegroundColor = .secondaryLabel
            button.configuration = config
            button.addAction(UIAction { [weak self] _ in self?.configuration?.onModifier(flag) }, for: .primaryActionTriggered)
            modifierButtons[flag] = button; modifierStack.addArrangedSubview(button)
        }
        root.targets = [scroll, keyboard.view, modifierContainer]
        let center = NotificationCenter.default
        for name in [UIAccessibility.reduceTransparencyStatusDidChangeNotification, UIContentSizeCategory.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMaterial(); self?.view.setNeedsLayout() }
            })
        }
        updateMaterial()
    }
    private func updateMaterial() {
        mode.updateMaterial()
        if UIAccessibility.isReduceTransparencyEnabled {
            actionsGlass.effect = nil; actionsGlass.backgroundColor = .secondarySystemBackground
            modifierContainer.effect = nil
        } else if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .clear)
            // Apple owns press scaling, elastic dragging and spring-back.
            // Do not add a custom transform, shader or competing pan recognizer.
            effect.isInteractive = true
            actionsGlass.effect = effect; actionsGlass.backgroundColor = .clear
            modifierContainer.effect = UIGlassContainerEffect()
        } else {
            actionsGlass.effect = UIBlurEffect(style: .systemMaterial)
            modifierContainer.effect = nil
        }
    }
    func configure(_ value: ChordControlRail) {
        loadViewIfNeeded(); configuration = value
        root.isHidden = !value.visible
        menu.configure(symbol: "slider.horizontal.3", title: "远程控制菜单", identifier: "remote-options", sections: value.menuSections,
                       primaryAction: nil, onPresentation: value.onPresentation, onSelect: value.onMenu)
        display.configure(symbol: "display.2", title: "显示器与文字大小", identifier: "display-dock-button", sections: [],
                          primaryAction: value.onDisplay, onPresentation: { _ in }, onSelect: { _ in })
        overview.configure(symbol: "rectangle.3.group", title: "窗口总览", identifier: "overview-dock-button", sections: [.init(items: [
            .init(id: "overview-show", title: "打开窗口总览", symbol: "rectangle.3.group", enabled: value.inputAllowed),
            .init(id: "overview-hide", title: "退出窗口总览", symbol: "rectangle", enabled: value.inputAllowed)
        ])], primaryAction: { value.onOverview(.show) }, onPresentation: value.onPresentation, onSelect: value.onMenu)
        keyboard.configure(symbol: value.keyboardShown ? "keyboard.chevron.compact.down" : "keyboard",
                           title: value.keyboardShown ? "收起键盘／快捷菜单" : "显示键盘／快捷菜单", identifier: "keyboard-dock-toggle",
                           sections: value.keyboardSections, primaryAction: value.onKeyboard,
                           onPresentation: value.onPresentation, onSelect: value.onKeyboardMenu, glass: true)
        keyboard.button.accessibilityHint = "轻点显示或收起键盘，长按打开快捷菜单"
        overview.button.accessibilityHint = "轻点打开总览；长按可选择退出"
        display.view.isHidden = !value.showDisplay; overview.view.isHidden = !value.showOverview
        mode.isHidden = !value.showMode; mode.refreshSymbols(); mode.select(value.mode)
        modifierContainer.isHidden = !value.keyboardShown
        for (flag, button) in modifierButtons {
            button.isSelected = value.modifiers & flag != 0
            button.accessibilityValue = button.isSelected ? "已按下，下一次快捷键后释放" : "未按下"
        }
        view.setNeedsLayout()
    }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); view.setNeedsLayout() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let c = configuration, let window = view.window else { return }
        let preferred = max(keyboard.buttonDiameter, mode.intrinsicContentSize.width)
        guard preferred > 0 else { return }
        let systemBar: CGRect?
        if #available(iOS 27.1, *) {
            systemBar = view.convert(window.bounds.inset(by: window.edgeInsets(for: .bar(onEdge: .trailing, extent: preferred))), from: window)
        } else { systemBar = nil }
        // Older systems have no trailing-bar region. Keep the canvas full bleed,
        // but derive the controls' vertical limits from the window's public guide.
        let safeFrame = view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window)
        let fallbackTop = max(view.bounds.minY, safeFrame.minY)
        let fallbackBottom = min(view.bounds.maxY, safeFrame.maxY)
        let fallback = CGRect(x: view.bounds.minX, y: fallbackTop, width: view.bounds.width,
                              height: max(0, fallbackBottom - fallbackTop))
        let column = ControlRailPosition.column(in: fallback, barRegion: systemBar,
            margin: systemMinimumLayoutMargins.trailing, preferredWidth: preferred)
        let side = column.width, width = side
        let area = column
        let anchor = column.midX
        let keyboardY = c.keyboardTop.map { view.convert(CGPoint(x: 0, y: $0), from: nil).y }
        let lower = min(area.maxY, keyboardY ?? area.maxY)
        let offset = keyboardY == nil ? view.bounds.height * ControlRailPosition.fraction(c.bottomOffset, maximum: 0.30) : 0
        keyboard.view.frame = CGRect(x: anchor - side / 2, y: max(area.minY, lower - side - 8 - offset), width: side, height: side)
        let statusBottom = view.convert(CGPoint(x: 0, y: c.statusBottom), from: nil).y
        let glassOutset = side / 2
        // Reserve the elastic material's breathing room as well as the resting
        // button frame, so a press cannot grow into the status strip above it.
        let top = max(area.minY, statusBottom) + glassOutset + 8 + view.bounds.height * ControlRailPosition.fraction(c.topOffset, maximum: 0.25)
        scroll.glassOutset = glassOutset
        scroll.frame = CGRect(x: anchor - width / 2 - glassOutset, y: top - glassOutset,
                              width: width + glassOutset * 2,
                              height: max(0, keyboard.view.frame.minY - top - 12) + glassOutset * 2)
        let count = stack.arrangedSubviews.filter { !$0.isHidden }.count
        actionsGlass.frame = CGRect(x: glassOutset + (width - side) / 2, y: glassOutset, width: side, height: side * CGFloat(count) + 12)
        if #unavailable(iOS 26.0) { actionsGlass.layer.cornerRadius = side / 2 }
        actionsGlass.clipsToBounds = false
        stack.frame = actionsGlass.bounds.insetBy(dx: 0, dy: 6)
        mode.frame = CGRect(x: glassOutset + (width - side) / 2, y: actionsGlass.frame.maxY + 12, width: side, height: max(mode.intrinsicContentSize.height, side * 2))
        scroll.contentSize = CGSize(width: width + glassOutset * 2, height: (c.showMode ? mode.frame.maxY : actionsGlass.frame.maxY) + glassOutset)
        let modifiersSize = CGSize(width: side * CGFloat(modifierButtons.count) + modifierStack.spacing * CGFloat(max(0, modifierButtons.count - 1)), height: side)
        modifierContainer.frame = CGRect(x: keyboard.view.frame.minX - modifiersSize.width - 8, y: keyboard.view.frame.minY,
                                         width: modifiersSize.width, height: modifiersSize.height)
        modifierStack.frame = modifierContainer.bounds
        let global = view.convert(CGRect(x: column.minX, y: area.minY, width: width, height: max(0, lower - area.minY)), to: nil)
        let globalAnchor = view.convert(CGPoint(x: anchor, y: 0), to: nil).x
        if global != lastGeometry || lastAnchor != globalAnchor {
            lastGeometry = global; lastAnchor = globalAnchor
#if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["DUO_UI_FIXTURE"] == "1" {
                root.accessibilityIdentifier = "rail-layout-metrics"
                root.accessibilityValue = "barX=\(column.midX);barWidth=\(column.width);symbol=\(RailSymbol.extent)"
            }
#endif
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastGeometry == global, self.lastAnchor == globalAnchor else { return }
                self.configuration?.onGeometry(global, globalAnchor)
            }
        }
    }
    func cancelMenus() { [menu, display, overview, keyboard].forEach { $0.cancelMenu() } }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
#endif
