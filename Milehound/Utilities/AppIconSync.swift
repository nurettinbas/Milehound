import ObjectiveC
import SwiftUI
import UIKit

private final class RotationPaintRelay: NSObject, @unchecked Sendable {
    static let shared = RotationPaintRelay()

    @objc func tick() {
        MainActor.assumeIsolated {
            AppIconSync.tickRotationPaint()
        }
    }
}

/// Maps `ShellPalette` to a bundled alternate Home Screen icon.
/// Sky keeps the primary Liquid Glass icon (`Milehound.icon`, alternate name `nil`).
enum AppIconSync {
    @MainActor private static var pendingTask: Task<Void, Never>?
    @MainActor private static var inFlightTarget: String?

    static func alternateIconName(for palette: ShellPalette) -> String? {
        guard palette != .sky else { return nil }
        let raw = palette.rawValue
        let first = raw.prefix(1).uppercased(with: Locale(identifier: "en_US_POSIX"))
        return "AppIcon\(first)\(raw.dropFirst())"
    }

    static var alternateIconNames: [String] {
        ShellPalette.allCases.compactMap { alternateIconName(for: $0) }
    }

    static func needsUpdate(currentAlternateIconName: String?, palette: ShellPalette) -> Bool {
        alternateIconName(for: palette) != currentAlternateIconName
    }

    @MainActor
    static func apply(_ palette: ShellPalette) {
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let targetName = alternateIconName(for: palette)
        let targetKey = targetName ?? "__primary__"
        guard UIApplication.shared.alternateIconName != targetName,
              inFlightTarget != targetKey else { return }

        // Coalesce repeated SwiftUI changes before asking iOS. The public API
        // always presents exactly one system confirmation.
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            guard UIApplication.shared.alternateIconName != targetName,
                  inFlightTarget != targetKey else { return }

            syncWindowStyle(AppSettings.shared.appearanceMode)
            await Task.yield()
            guard !Task.isCancelled else { return }

            inFlightTarget = targetKey
            UIApplication.shared.setAlternateIconName(targetName) { error in
                Task { @MainActor in
                    inFlightTarget = nil
                    if let error {
                        DevLog.shared.error(.general, "App icon sync failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Keeps UIKit windows on the same Light/Dark as SwiftUI `preferredColorScheme`.
    /// Nav title ink stays in SwiftUI (`onGlassShell`).
    /// The window fill is the shell mid color so rotation does not flash the system white
    /// in the wedges the rotating view does not cover.
    @MainActor
    static func syncWindowStyle(
        _ mode: AppearanceMode,
        palette: ShellPalette = AppSettings.shared.shellPalette
    ) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where isAppWindow(window) {
                if window.overrideUserInterfaceStyle != style {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
        paintRotationSurfaces(palette: palette)
    }

    /// Install once, before the first rotation. Layout finishes by painting the shell
    /// back over the white plate UIKit inserts while the bounds change.
    static func installRotationHook() {
        RotationLayoutHook.install()
    }

    @MainActor
    static var isPaintingRotation: Bool {
        CACurrentMediaTime() < paintUntil
    }

    /// Page tabs and hosting views snap to system white for a frame while the
    /// window resizes. Repaint through that window so the shell stays visible.
    @MainActor
    static func beginRotationPaint() {
        installRotationHook()
        paintUntil = CACurrentMediaTime() + 0.9
        paintRotationSurfaces(palette: AppSettings.shared.shellPalette)
        guard paintLink == nil else { return }
        let link = CADisplayLink(target: RotationPaintRelay.shared, selector: #selector(RotationPaintRelay.tick))
        link.add(to: .main, forMode: .common)
        paintLink = link
    }

    @MainActor
    static func tickRotationPaint() {
        paintRotationSurfaces(palette: AppSettings.shared.shellPalette)
        guard CACurrentMediaTime() >= paintUntil else { return }
        paintLink?.invalidate()
        paintLink = nil
    }

    @MainActor
    static func paintRotationSurfaces(palette: ShellPalette) {
        guard !isInsidePaint else { return }
        isInsidePaint = true
        defer { isInsidePaint = false }
        let fill = rotationFill(palette: palette)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where isAppWindow(window) {
                let traits = window.traitCollection
                let resolved = fill.resolvedColor(with: traits)
                if !isShellFill(window.backgroundColor, traits: traits) {
                    window.backgroundColor = resolved
                }
                guard let root = window.rootViewController?.view else { continue }
                if !isShellFill(root.backgroundColor, traits: traits) {
                    root.backgroundColor = resolved
                    root.layer.backgroundColor = resolved.cgColor
                }
                // Cells, fields, and bars keep their own fill. Scroll views are cleared
                // even when their white is not a readable UIColor — the page tab resets
                // that plate after the display link has already run.
                var pending: [UIView] = [window]
                while let view = pending.popLast() {
                    let name = String(describing: type(of: view))
                    if name.contains("Cell") || view is UITextView { continue }
                    if view !== root {
                        let bounds = view.bounds
                        let area = bounds.width * bounds.height
                        let skipsChrome = name.contains("Bar") || name.contains("Button") || name.contains("Field")
                            || name.contains("Effect") || name.contains("Label") || name.contains("Image")
                        let whitePlate = isNearWhite(view.backgroundColor, traits: traits)
                            || isNearWhite(view.layer.backgroundColor.map { UIColor(cgColor: $0) }, traits: traits)
                        if !skipsChrome, area > 8_000, view is UIScrollView || whitePlate {
                            if view.backgroundColor != .clear {
                                view.backgroundColor = .clear
                            }
                            if view.isOpaque {
                                view.isOpaque = false
                            }
                            if view.layer.backgroundColor != nil {
                                view.layer.backgroundColor = nil
                            }
                        }
                    }
                    pending.append(contentsOf: view.subviews)
                }
            }
        }
    }

    private static func isShellFill(_ color: UIColor?, traits: UITraitCollection) -> Bool {
        guard let color, color != .clear else { return false }
        return !isNearWhite(color, traits: traits)
    }

    private static func isNearWhite(_ color: UIColor?, traits: UITraitCollection) -> Bool {
        guard let color else { return false }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let resolved = color.resolvedColor(with: traits)
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return alpha > 0.85 && red > 0.94 && green > 0.94 && blue > 0.94
    }

    /// Key window plus every normal window. Unfolding the Duo resizes a window that
    /// is not key for a frame; painting only the key window left that canvas white.
    @MainActor
    static func isAppWindow(_ window: UIWindow) -> Bool {
        let name = String(describing: type(of: window))
        if name.contains("Keyboard") || name.contains("TextEffects") { return false }
        let key = window.isKeyWindow
        let level = window.windowLevel
        return key || level == .normal
    }

    @MainActor private static var paintLink: CADisplayLink?
    @MainActor private static var paintUntil: CFTimeInterval = 0
    @MainActor private static var isInsidePaint = false

    /// Solid stand-in for the atmosphere gradient. A dynamic color tracks system Light/Dark
    /// when Appearance is System; a forced style resolves through the window's override.
    private static func rotationFill(palette: ShellPalette) -> UIColor {
        UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            let rgb = palette.atmosphere(for: scheme).mid
            return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }
    }
}

/// Starts the shell repaint when the window size changes, before the rotation snapshot settles.
struct WindowRotationFill: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WindowRotationFillController {
        WindowRotationFillController()
    }

    func updateUIViewController(_ controller: WindowRotationFillController, context: Context) {}
}

final class WindowRotationFillController: UIViewController {
    private var lastSize: CGSize = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        MainActor.assumeIsolated {
            AppIconSync.beginRotationPaint()
        }
        coordinator.animate(alongsideTransition: { _ in
            MainActor.assumeIsolated {
                AppIconSync.beginRotationPaint()
            }
        })
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let size = MainActor.assumeIsolated { view.bounds.size }
        let previous = lastSize
        lastSize = size
        guard previous != .zero, size != .zero, previous != size else { return }
        MainActor.assumeIsolated {
            AppIconSync.beginRotationPaint()
        }
    }
}

private enum RotationLayoutHook {
    private static let token: Void = {
        exchange(
            UIViewController.self,
            #selector(UIViewController.viewWillTransition(to:with:)),
            #selector(UIViewController.milehound_viewWillTransition(to:with:))
        )
        installWindowLayout()
    }()

    static func install() {
        _ = token
    }

    private static func exchange(_ cls: AnyClass, _ original: Selector, _ swizzled: Selector) {
        guard let current = class_getInstanceMethod(cls, original),
              let replacement = class_getInstanceMethod(cls, swizzled) else { return }
        method_exchangeImplementations(current, replacement)
    }

    /// After the window lays its subviews out, before the frame is drawn.
    /// A display link runs too early: UIKit paints the white plate back over it.
    private static func installWindowLayout() {
        let selector = #selector(UIView.layoutSubviews)
        guard declares(UIWindow.self, selector) else {
            addWindowLayout(selector)
            return
        }
        exchange(UIWindow.self, selector, #selector(UIWindow.milehound_layoutSubviews))
    }

    private static func declares(_ cls: AnyClass, _ selector: Selector) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            return true
        }
        return false
    }

    private static func addWindowLayout(_ selector: Selector) {
        guard let viewMethod = class_getInstanceMethod(UIView.self, selector) else { return }
        let encoding = method_getTypeEncoding(viewMethod)
        let block: @convention(block) (UIWindow) -> Void = { window in
            let implementation = method_getImplementation(viewMethod)
            typealias Layout = @convention(c) (UIWindow, Selector) -> Void
            unsafeBitCast(implementation, to: Layout.self)(window, selector)
            MainActor.assumeIsolated {
                guard AppIconSync.isPaintingRotation else { return }
                AppIconSync.paintRotationSurfaces(palette: AppSettings.shared.shellPalette)
            }
        }
        class_addMethod(UIWindow.self, selector, imp_implementationWithBlock(block), encoding)
    }
}

extension UIWindow {
    @objc func milehound_layoutSubviews() {
        milehound_layoutSubviews()
        MainActor.assumeIsolated {
            guard AppIconSync.isPaintingRotation else { return }
            AppIconSync.paintRotationSurfaces(palette: AppSettings.shared.shellPalette)
        }
    }
}

extension UIViewController {
    /// A cancelled turn can leave the hosting view rotated inside the new display.
    /// Identity restores upright layout; the scene then applies the orientation it already wants.
    @discardableResult
    fileprivate func restoreUprightInterface() -> Bool {
        var stuck: [UIView] = []
        var current: UIView? = view
        var steps = 0
        while let candidate = current, steps < 12 {
            if !candidate.transform.isIdentity {
                stuck.append(candidate)
            }
            if candidate is UIWindow { break }
            current = candidate.superview
            steps += 1
        }
        guard !stuck.isEmpty else { return false }
        UIView.performWithoutAnimation {
            for candidate in stuck {
                candidate.transform = .identity
            }
        }
        setNeedsUpdateOfSupportedInterfaceOrientations()
        return true
    }

    /// The turn to portrait was cancelled and the interface is still landscape.
    /// Ask once, after the gesture has settled, so the Duo can stand upright.
    fileprivate func repairCancelledOrientation(target: CGSize) {
        let targetPortrait = target.height > target.width
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !MilehoundInterfaceRotation.shared.isRotating else { return }
            guard let scene = self.view.window?.windowScene else { return }
            let interfacePortrait = scene.interfaceOrientation.isPortrait
            guard targetPortrait != interfacePortrait else { return }
            guard MilehoundInterfaceRotation.shared.shouldRepairOrientation() else { return }
            let mask: UIInterfaceOrientationMask = targetPortrait ? .portrait : .landscape
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }

    @objc func milehound_viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let transition = MainActor.assumeIsolated { () -> (paint: Bool, turn: Bool) in
            let isRoot = view.window?.rootViewController === self
            let bounds = view.bounds.size
            let sizeChanges = bounds != size
            let aspectFlips = sizeChanges && bounds.width > 1 && bounds.height > 1
                && (bounds.width > bounds.height) != (size.width > size.height)
            let transformTurns = coordinator.targetTransform != .identity
            return (isRoot && sizeChanges, isRoot && (aspectFlips || transformTurns))
        }
        if transition.paint {
            MainActor.assumeIsolated {
                AppIconSync.beginRotationPaint()
            }
        }
        if transition.turn {
            MainActor.assumeIsolated {
                MilehoundInterfaceRotation.shared.begin()
            }
        }
        milehound_viewWillTransition(to: size, with: coordinator)
        guard transition.paint || transition.turn else { return }
        coordinator.animate(alongsideTransition: { _ in
            guard transition.paint else { return }
            MainActor.assumeIsolated {
                AppIconSync.paintRotationSurfaces(palette: AppSettings.shared.shellPalette)
            }
        }, completion: { context in
            let cancelled = context.isCancelled
            MainActor.assumeIsolated {
                if transition.turn {
                    MilehoundInterfaceRotation.shared.end()
                }
                guard cancelled else { return }
                self.restoreUprightInterface()
                self.repairCancelledOrientation(target: size)
            }
        })
    }
}
