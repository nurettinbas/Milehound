import SwiftUI
import UIKit

/// Selected-tab color is the palette tint for the current appearance.
/// The bar itself stays the system Light / Dark Liquid Glass tab — portrait
/// and landscape. Do not recolor the glass blob or pin a tab to the other scheme.
enum MilehoundTabBarTheme {
    /// Segmented controls. Light keeps the vivid dark-recipe tint.
    static func selectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        let hue = scheme == .light
            ? palette.atmosphere(for: .dark).tint
            : palette.atmosphere(for: scheme).tint
        return uiColor(hue)
    }

    /// Selected tab icon and title. Same ink as the palette the user picked.
    static func selectionTintUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        uiColor(palette.atmosphere(for: scheme).tint)
    }

    static func selectedGlyphUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        selectionTintUIColor(palette: palette, scheme: scheme)
    }

    static func uiColor(_ rgb: ShellRGB, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func pagePlateUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        uiColor(palette.atmosphere(for: scheme).mid)
    }

    static func clearGlassTintUIColor(palette: ShellPalette) -> UIColor {
        uiColor(
            GlassContrast.nativeGlassTint(palette: palette),
            alpha: CGFloat(GlassContrast.tabBarClearGlassTintOpacity)
        )
    }

    /// Outline + fill SF Symbol per tab. Recap uses `star.fill` — `sparkles.fill` /
    /// `sparkle.fill` are missing, so selected Recap was a transparent hole on ice.
    static let itemSymbols: [(outline: String, fill: String)] = [
        ("map", "map.fill"),
        ("car", "car.fill"),
        ("chart.bar", "chart.bar.fill"),
        ("star", "star.fill"),
        ("gearshape", "gearshape.fill")
    ]
}

/// A screen that hid the tab bar with `.toolbar(.hidden, for: .tabBar)` sets this, so the
/// installer below does not force the bar back on.
@MainActor
@Observable
final class MilehoundTabBarVisibility {
    static let shared = MilehoundTabBarVisibility()
    var hiddenByScreen = false
}

/// System iOS 26 `UITabBar`. Light and Dark keep the system Liquid Glass platter.
/// The selection capsule and its icon use the palette tint — iOS otherwise paints
/// that capsule with `AccentColor` (blue) on every theme. Do not copy
/// `UITabBarAppearance` on iOS 26.
@MainActor
enum MilehoundTabBarCompact {
    private enum SelectionImageStamp {
        @MainActor static var key: UInt8 = 0
    }
    static func apply(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        if !MilehoundTabBarVisibility.shared.hiddenByScreen {
            tabBar.isHidden = false
            tabBar.alpha = 1
        }
        restoreSystemWidthIfNeeded(tabBar)
        clearInterfaceStylePin(tabBar)
        clearItemInterfaceStylePins(in: tabBar)
        applySelectionTint(to: tabBar, palette: palette, scheme: scheme)

        if #available(iOS 26.0, *) { return }

        let selected = MilehoundTabBarTheme.selectionTintUIColor(palette: palette, scheme: scheme)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        applyItemColors(to: appearance, selected: selected, unselected: .secondaryLabel)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    /// Selected icon and title. Unselected stays the system liquid-glass ink.
    static func applySelectionTint(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        let selected = MilehoundTabBarTheme.selectionTintUIColor(palette: palette, scheme: scheme)
        if !sameColor(tabBar.tintColor, selected) {
            tabBar.tintColor = selected
        }
        if tabBar.unselectedItemTintColor != nil {
            tabBar.unselectedItemTintColor = nil
        }
        tintSelectionChrome(on: tabBar, tint: selected)
    }

    /// True once the selection capsule exists and wears the palette tint.
    static func selectionGlassIsReady(_ tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) -> Bool {
        guard #available(iOS 26.0, *) else { return true }
        let tint = MilehoundTabBarTheme.selectionTintUIColor(palette: palette, scheme: scheme)
        if selectionGlassMatches(in: tabBar, tabBar: tabBar, tint: tint, requireCenterOnBar: false) {
            return true
        }
        guard let superview = tabBar.superview else { return false }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            if selectionGlassMatches(in: sibling, tabBar: tabBar, tint: tint, requireCenterOnBar: true) {
                return true
            }
        }
        return false
    }

    /// Palette wash on the selection capsule only. The tall/wide platter stays clear
    /// so the bar remains the system Liquid Glass tab.
    private static func tintSelectionChrome(on tabBar: UITabBar, tint: UIColor) {
        tintSelectionChrome(
            in: tabBar,
            tabBar: tabBar,
            tint: tint,
            requireCenterOnBar: false,
            insideSelection: false
        )
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            tintSelectionChrome(
                in: sibling,
                tabBar: tabBar,
                tint: tint,
                requireCenterOnBar: true,
                insideSelection: false
            )
        }
    }

    private static func tintSelectionChrome(
        in view: UIView,
        tabBar: UITabBar,
        tint: UIColor,
        requireCenterOnBar: Bool,
        insideSelection: Bool
    ) {
        var childInsideSelection = insideSelection
        if #available(iOS 26.0, *) {
            if let effectView = view as? UIVisualEffectView,
               let glass = effectView.effect as? UIGlassEffect,
               effectView.bounds.width > 8,
               effectView.bounds.height > 8,
               !requireCenterOnBar || centerIsOnBar(effectView, bar: tabBar) {
                if isPlatter(effectView, matching: tabBar) {
                    if sameColor(glass.tintColor, tint) {
                        glass.tintColor = nil
                        effectView.effect = glass
                    }
                } else if !sameColor(glass.tintColor, tint) {
                    glass.tintColor = tint
                    effectView.effect = glass
                    childInsideSelection = true
                } else {
                    childInsideSelection = true
                }
            }
        }

        let onBar = !requireCenterOnBar || centerIsOnBar(view, bar: tabBar)
        let selectedControl = tabItemControl(containing: view)?.isSelected == true
        let paintsSelection = onBar && (insideSelection || childInsideSelection || selectedControl)

        if let imageView = view as? UIImageView, paintsSelection, let source = imageView.image {
            // Same symbol, same size. Template mode takes the palette tint.
            // Redrawing the glyph shrinks it inside the tab slot.
            let stamped = objc_getAssociatedObject(imageView, &SelectionImageStamp.key) as? UIImage
            if stamped !== source || !sameColor(imageView.tintColor, tint) {
                let colored = tintedSelectionImage(source, tint: tint)
                imageView.tintColor = tint
                imageView.image = colored
                objc_setAssociatedObject(
                    imageView,
                    &SelectionImageStamp.key,
                    colored,
                    .OBJC_ASSOCIATION_RETAIN
                )
            }
        } else if let imageView = view as? UIImageView, onBar, sameColor(imageView.tintColor, tint) {
            imageView.tintColor = nil
            objc_setAssociatedObject(imageView, &SelectionImageStamp.key, nil, .OBJC_ASSOCIATION_RETAIN)
        }

        if let label = view as? UILabel, paintsSelection, !sameColor(label.textColor, tint) {
            let text = (label.text ?? label.attributedText?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            label.textColor = tint
            label.tintColor = tint
            if !text.isEmpty {
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: tint]
                if let font = label.font { attributes[.font] = font }
                label.attributedText = NSAttributedString(string: text, attributes: attributes)
            }
        }

        if let effectView = view as? UIVisualEffectView {
            tintSelectionChrome(
                in: effectView.contentView,
                tabBar: tabBar,
                tint: tint,
                requireCenterOnBar: requireCenterOnBar,
                insideSelection: childInsideSelection
            )
        }
        for subview in view.subviews {
            tintSelectionChrome(
                in: subview,
                tabBar: tabBar,
                tint: tint,
                requireCenterOnBar: requireCenterOnBar,
                insideSelection: childInsideSelection
            )
        }
    }

    @available(iOS 26.0, *)
    private static func selectionGlassMatches(
        in view: UIView,
        tabBar: UITabBar,
        tint: UIColor,
        requireCenterOnBar: Bool
    ) -> Bool {
        if let effectView = view as? UIVisualEffectView,
           let glass = effectView.effect as? UIGlassEffect,
           !isPlatter(effectView, matching: tabBar),
           !requireCenterOnBar || centerIsOnBar(effectView, bar: tabBar),
           sameColor(glass.tintColor, tint) {
            return true
        }
        if let effectView = view as? UIVisualEffectView,
           selectionGlassMatches(
               in: effectView.contentView,
               tabBar: tabBar,
               tint: tint,
               requireCenterOnBar: requireCenterOnBar
           ) {
            return true
        }
        for subview in view.subviews {
            if selectionGlassMatches(
                in: subview,
                tabBar: tabBar,
                tint: tint,
                requireCenterOnBar: requireCenterOnBar
            ) {
                return true
            }
        }
        return false
    }

    /// Glass platter in window coordinates. A side tab's `UITabBar` is the full
    /// column, including the empty space under the Wi-Fi. The visible icon pill
    /// is the frame the capsule lines up with. Falls back to the bar itself.
    private static var cachedSidePill: (bar: CGRect, pill: CGRect)?

    static func platterFrame(of tabBar: UITabBar, in window: UIWindow) -> CGRect {
        if tabBar.bounds.height > tabBar.bounds.width * 1.4 {
            let bar = tabBar.convert(tabBar.bounds, to: window)
            if let cached = cachedSidePill, sameFrame(cached.bar, bar) {
                return cached.pill
            }
            if let icons = sideIconUnion(in: window, column: bar) {
                cachedSidePill = (bar, icons)
                return icons
            }
            if let pill = sideIconPill(in: window, bar: bar) {
                cachedSidePill = (bar, pill)
                return pill
            }
        }
        if #available(iOS 26.0, *), let platter = glassPlatter(matching: tabBar) {
            let frame = platter.convert(platter.bounds, to: window)
            if frame.width > 8, frame.height > 8 { return frame }
        }
        return tabBar.convert(tabBar.bounds, to: window)
    }

    /// Visible glass pill of a side tab, in window coordinates. `platterFrame` is the
    /// icon union, which stops short of the pill's rounded ends.
    static func sidePillFrame(of tabBar: UITabBar, in window: UIWindow) -> CGRect? {
        guard tabBar.bounds.height > tabBar.bounds.width * 1.4 else { return nil }
        let bar = tabBar.convert(tabBar.bounds, to: window)
        if let cached = cachedVisiblePill, sameFrame(cached.bar, bar) {
            return cached.pill
        }
        guard let pill = sideIconPill(in: window, bar: bar) else { return nil }
        cachedVisiblePill = (bar, pill)
        return pill
    }

    private static var cachedVisiblePill: (bar: CGRect, pill: CGRect)?

    /// Union of the tab icons. The column view itself runs up under the clock;
    /// the icons start lower, and that top is what the bell has to clear.
    private static func sideIconUnion(in window: UIWindow, column: CGRect) -> CGRect? {
        var union: CGRect?
        func walk(_ view: UIView) {
            let frame = view.convert(view.bounds, to: window)
            let icon = frame.height >= 28 && frame.height <= 76
                && frame.width >= 28 && frame.width <= column.width + 20
                && frame.midX >= column.minX - 10 && frame.midX <= column.maxX + 10
                && frame.minY > 120
            if icon {
                union = union.map { $0.union(frame) } ?? frame
            }
            for subview in view.subviews where subview.alpha > 0.01 && !subview.isHidden {
                walk(subview)
            }
        }
        walk(window)
        guard let union, union.height > 100 else { return nil }
        return union
    }

    /// Tall glass capsule of side-tab icons, in window coordinates.
    /// The column itself runs under the Wi-Fi; the icons start lower.
    private static func sideIconPill(in window: UIWindow, bar: CGRect) -> CGRect? {
        var best: CGRect?
        func walk(_ view: UIView) {
            let frame = view.convert(view.bounds, to: window)
            let isPill = frame.height > frame.width * 1.4
                && frame.height > 120
                && frame.height < bar.height * 0.9
                && frame.width > 30
                && frame.minX >= bar.minX - 20
                && frame.maxX <= bar.maxX + 20
            if isPill, best == nil || frame.height > (best?.height ?? 0) {
                best = frame
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        walk(window)
        return best
    }

    private static func sameFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    @available(iOS 26.0, *)
    private static func glassPlatter(matching tabBar: UITabBar) -> UIView? {
        if let found = findGlassPlatter(in: tabBar, matching: tabBar) { return found }
        guard let superview = tabBar.superview else { return nil }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            if let found = findGlassPlatter(in: sibling, matching: tabBar) { return found }
        }
        return nil
    }

    @available(iOS 26.0, *)
    private static func findGlassPlatter(in view: UIView, matching tabBar: UITabBar) -> UIView? {
        if let effectView = view as? UIVisualEffectView, isPlatter(effectView, matching: tabBar) {
            return effectView
        }
        if let effectView = view as? UIVisualEffectView,
           let found = findGlassPlatter(in: effectView.contentView, matching: tabBar) {
            return found
        }
        for subview in view.subviews {
            if let found = findGlassPlatter(in: subview, matching: tabBar) { return found }
        }
        return nil
    }

    /// Bottom platter is wide. Side platter is tall. The selection capsule is neither.
    private static func isPlatter(_ effectView: UIView, matching tabBar: UITabBar) -> Bool {
        let width = effectView.bounds.width
        let height = effectView.bounds.height
        let barWidth = tabBar.bounds.width
        let barHeight = tabBar.bounds.height
        guard width > 8, height > 8, barWidth > 8, barHeight > 8 else { return false }
        if barHeight > barWidth * 1.4 {
            return height > barHeight * 0.72
        }
        return width > barWidth * 0.55 && height > 36
    }

    private static func centerIsOnBar(_ view: UIView, bar: UITabBar) -> Bool {
        let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: bar)
        return bar.bounds.insetBy(dx: -8, dy: -8).contains(center)
    }

    private static func tabItemControl(containing view: UIView) -> UIControl? {
        var node: UIView? = view
        while let current = node {
            if let control = current as? UIControl, !(current is UITabBar) {
                return control
            }
            node = current.superview
        }
        return nil
    }

    /// Palette ink on the system symbol. Does not redraw it, so the tab slot keeps its size.
    static func tintedSelectionImage(_ image: UIImage, tint: UIColor) -> UIImage {
        image.withTintColor(tint, renderingMode: .alwaysTemplate)
    }

    private static func sameColor(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
            guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
                  rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else {
                return lhs.isEqual(rhs)
            }
            return abs(lr - rr) < 0.02 && abs(lg - rg) < 0.02 && abs(lb - rb) < 0.02 && abs(la - ra) < 0.02
        default:
            return false
        }
    }

    private static func clearInterfaceStylePin(_ tabBar: UITabBar) {
        if tabBar.overrideUserInterfaceStyle != .unspecified {
            tabBar.overrideUserInterfaceStyle = .unspecified
        }
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            if sibling.overrideUserInterfaceStyle != .unspecified {
                sibling.overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    private static func clearItemInterfaceStylePins(in view: UIView) {
        if let control = view as? UIControl, !(view is UITabBar),
           control.overrideUserInterfaceStyle != .unspecified {
            control.overrideUserInterfaceStyle = .unspecified
        }
        for subview in view.subviews {
            clearItemInterfaceStylePins(in: subview)
        }
    }

    /// Bottom chrome sits under the bar. Side chrome sits in the leading column.
    private static func isTabChromeSibling(_ sibling: UIView, of tabBar: UITabBar) -> Bool {
        let bar = tabBar.frame
        let frame = sibling.frame
        if bar.height > bar.width * 1.4 {
            let overlapsY = frame.maxY > bar.minY - 24 && frame.minY < bar.maxY + 24
            let nearX = abs(frame.midX - bar.midX) < max(bar.width, 80) + 48
            let notContent = frame.width < bar.width + 180
            return overlapsY && nearX && notContent
        }
        return frame.maxY >= bar.minY - 40 && frame.height <= bar.height + 120
    }

    /// Undo a leftover narrow frame from the old compact hack. Skip once the bar is full width.
    /// A side tab bar is supposed to be narrow — stretching it wipes the liquid glass column.
    static func restoreSystemWidthIfNeeded(_ tabBar: UITabBar) {
        guard tabBar.bounds.width >= tabBar.bounds.height else { return }
        guard let superview = tabBar.superview else { return }
        let fullWidth = superview.bounds.width
        guard fullWidth > 0, tabBar.bounds.width > 0, tabBar.bounds.width < fullWidth * 0.92 else { return }

        tabBar.itemPositioning = .automatic
        tabBar.itemSpacing = 0
        tabBar.itemWidth = 0

        var frame = tabBar.frame
        frame.origin.x = superview.bounds.minX
        frame.size.width = fullWidth
        tabBar.frame = frame
    }

    private static func applyItemColors(
        to appearance: UITabBarAppearance,
        selected: UIColor,
        unselected: UIColor
    ) {
        let layouts = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for layout in layouts {
            layout.normal.iconColor = unselected
            layout.normal.titleTextAttributes = [.foregroundColor: unselected]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        appearance.selectionIndicatorTintColor = selected
    }
}

/// Hosts a zero-size controller that walks the window and styles `UITabBar`.
struct MilehoundTabBarCompactInstaller: UIViewControllerRepresentable {
    var selectedTab: AppTab
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    func makeUIViewController(context: Context) -> MilehoundTabBarCompactController {
        let controller = MilehoundTabBarCompactController()
        controller.palette = shellPalette
        controller.colorScheme = colorScheme
        return controller
    }

    func updateUIViewController(_ uiViewController: MilehoundTabBarCompactController, context: Context) {
        uiViewController.palette = shellPalette
        uiViewController.colorScheme = colorScheme
        uiViewController.apply()
        uiViewController.publishChrome()
    }
}

final class MilehoundTabBarCompactController: UIViewController {
    var palette: ShellPalette = .sky
    var colorScheme: ColorScheme = .light
    private var glassRetryCount = 0
    private var glassRetryScheduled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        glassRetryCount = 0
        apply()
        publishChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        apply()
        publishChrome()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let chrome = SideColumnChromeState.shared
        chrome.beginTransition()
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            chrome.endTransition()
            self?.publishChrome()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard chrome.isTransitioning else { return }
            chrome.endTransition()
            self?.publishChrome()
        }
    }

    private var isPublishingChrome = false
    private var cachedColumnCover: (column: CGRect, bottom: CGFloat?)?

    /// Writes the platter frame the bell and merge stack share with the toolbar.
    /// Skipped while a rotation is in flight so neither copy draws from a stale frame.
    func publishChrome() {
        guard !isPublishingChrome else { return }
        isPublishingChrome = true
        defer { isPublishingChrome = false }
        let chrome = SideColumnChromeState.shared
        guard !chrome.isTransitioning else { return }
        guard let window = view.window ?? keyWindow() else { return }
        let tabBar = primaryTabBar()
        let frame = tabBar.map { MilehoundTabBarCompact.platterFrame(of: $0, in: window) }
        let pill = tabBar.flatMap { MilehoundTabBarCompact.sidePillFrame(of: $0, in: window) }
        let direction: LayoutDirection = window.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
        var status = statusClusterMaxY(in: window, column: frame)
        if let frame, frame.height > frame.width * 1.4,
           let cover = columnCoverBottom(in: window, column: frame) {
            status = max(status ?? 0, cover)
        }
        chrome.update(
            windowSize: window.bounds.size,
            safeInsets: window.safeAreaInsets,
            tabBarFrame: frame,
            sidePillFrame: pill,
            layoutDirection: direction,
            statusClusterMaxY: status
        )
    }

    /// Lowest chrome sitting in the tab column above the icons: the clock or the Wi-Fi
    /// when they hang below the status-bar frame.
    private func columnCoverBottom(in window: UIWindow, column: CGRect) -> CGFloat? {
        if let cached = cachedColumnCover,
           abs(cached.column.minX - column.minX) < 0.5,
           abs(cached.column.minY - column.minY) < 0.5,
           abs(cached.column.width - column.width) < 0.5,
           abs(cached.column.height - column.height) < 0.5 {
            return cached.bottom
        }
        var bottom: CGFloat?
        func walk(_ view: UIView) {
            let frame = view.convert(view.bounds, to: window)
            let inColumn = frame.midX >= column.minX - 16 && frame.midX <= column.maxX + 16
            let cover = inColumn
                && frame.maxY <= column.minY - 4
                && frame.minY < 180
                && frame.height >= 12 && frame.height <= 80
                && frame.width >= 12 && frame.width <= 160
            if cover {
                bottom = max(bottom ?? 0, frame.maxY)
            }
            for subview in view.subviews where subview.alpha > 0.01 && !subview.isHidden {
                walk(subview)
            }
        }
        walk(window)
        cachedColumnCover = (column, bottom)
        return bottom
    }

    /// Clock and Wi-Fi bottom, in window coordinates.
    /// The navigation bar sits beside the column, so its maxY is not the cluster.
    /// A collapsed status bar still draws the clock and Wi-Fi in the tab column.
    /// `collapsedStatusBottom` places that stack, including the Wi-Fi dots.
    /// A missing bar has no stack.
    private func statusClusterMaxY(in window: UIWindow, column: CGRect?) -> CGFloat? {
        let safe = window.safeAreaInsets
        guard let screen = window.windowScene?.screen,
              let manager = window.windowScene?.statusBarManager
        else { return safe.top <= 1 ? 0 : nil }
        let screenFrame = manager.statusBarFrame
        let inWindow = window.convert(screenFrame, from: screen.coordinateSpace)
        if screenFrame.height > 1, inWindow.maxY > 24 {
            return SideColumnChromeResolver.measuredStatusClusterMaxY(
                statusBarMaxY: inWindow.maxY,
                safeTop: safe.top
            )
        }
        if safe.top > 1 {
            return SideColumnChromeResolver.measuredStatusClusterMaxY(
                statusBarMaxY: safe.top,
                safeTop: safe.top
            )
        }
        if screenFrame.height > 0, screenFrame.height <= 8,
           let column, column.height > column.width * 1.4 {
            let onLeft = column.midX < window.bounds.midX
            let inset = onLeft ? safe.left : safe.right
            if inset > 20 {
                let portrait = window.bounds.height > window.bounds.width
                return SideColumnChromeResolver.collapsedStatusBottom(
                    columnInset: inset,
                    portrait: portrait
                )
            }
        }
        return 0
    }

    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
    }

    /// The root tab bar. A presented cover does not replace the column.
    private func primaryTabBar() -> UITabBar? {
        if let tabBar = tabBarController?.tabBar { return tabBar }
        if let root = view.window?.rootViewController ?? keyWindow()?.rootViewController {
            var found: UITabBar?
            func walk(_ controller: UIViewController) {
                if found != nil { return }
                if let tab = controller as? UITabBarController {
                    found = tab.tabBar
                    return
                }
                for child in controller.children { walk(child) }
            }
            walk(root)
            if let found { return found }
        }
        if let window = view.window ?? keyWindow() {
            return Self.visibleTabBar(in: window)
        }
        return nil
    }

    private static func visibleTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden, bar.bounds.width > 1 { return bar }
        for child in view.subviews {
            if let found = visibleTabBar(in: child) { return found }
        }
        return nil
    }

    func apply() {
        let bars = resolveTabBars()
        guard !bars.isEmpty else {
            scheduleGlassRetry()
            return
        }
        for tabBar in bars {
            MilehoundTabBarCompact.apply(to: tabBar, palette: palette, scheme: colorScheme)
        }
        let ready = bars.contains {
            MilehoundTabBarCompact.selectionGlassIsReady($0, palette: palette, scheme: colorScheme)
        }
        if ready {
            glassRetryCount = 0
        } else {
            scheduleGlassRetry()
        }
        publishChrome()
    }

    /// iOS 26 builds the selection capsule after the first layout. Until it exists,
    /// the bar keeps `AccentColor`.
    private func scheduleGlassRetry() {
        guard glassRetryCount < 12, !glassRetryScheduled else { return }
        glassRetryCount += 1
        glassRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.glassRetryScheduled = false
            self.apply()
        }
    }

    private func resolveTabBars() -> [UITabBar] {
        if let tabBar = tabBarController?.tabBar { return [tabBar] }
        guard let root = view.window?.rootViewController else { return [] }
        var bars: [UITabBar] = []
        func walk(_ controller: UIViewController) {
            if let tab = controller as? UITabBarController {
                bars.append(tab.tabBar)
            }
            for child in controller.children { walk(child) }
            if let presented = controller.presentedViewController { walk(presented) }
        }
        walk(root)
        return bars
    }
}
