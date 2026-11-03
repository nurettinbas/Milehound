import SwiftUI
import UIKit

enum SideColumnChromeID {
    static let notifications = "trips.notifications"
    static let merge = "trips.merge"
    static let newJournal = "trips.journal.new"
}

/// Where the bell and the Trips trailing action draw.
/// Toolbar and the side column read this together, so a rotation cannot show both.
enum SideColumnChromePlacement: Equatable {
    case toolbar
    /// Rotation or a missing platter. The toolbar keeps the buttons until the next platter.
    case pending
    /// `stackFrame` is in window coordinates. `below` is true when the camera
    /// would have covered the stack above the platter.
    case sideColumn(stackFrame: CGRect, below: Bool)

    var showsToolbarChrome: Bool {
        if case .toolbar = self { return true }
        return false
    }
}

struct SideColumnChromeMetrics: Equatable {
    var windowSize: CGSize
    var safeInsets: UIEdgeInsets
    var tabBarFrame: CGRect?
    var layoutDirection: LayoutDirection
    var buttonCount: Int
    var isTransitioning: Bool
    /// Bottom of the clock and Wi-Fi cluster, in window coordinates.
    /// Nil when `statusBarManager` did not report a frame.
    var statusClusterMaxY: CGFloat?
}

/// Pure placement for the side-column bell and merge (or new-travel) stack.
enum SideColumnChromeResolver {
    /// Clock and Wi-Fi bottom when the status bar is only a collapsed strip.
    /// Landscape keeps the stack inside the column inset. Portrait top-aligns it,
    /// then the Wi-Fi hangs one status row below. The glyph's dots extend past
    /// that edge, so the capsule starts clear of them.
    static func collapsedStatusBottom(columnInset: CGFloat, portrait: Bool) -> CGFloat {
        let statusRow: CGFloat = 54
        let glyphOverhang: CGFloat = 12
        let cluster = portrait ? columnInset + statusRow : columnInset
        return cluster + glyphOverhang
    }

    /// Bottom of the clock and Wi-Fi cluster. Nil when the status bar frame was not measured.
    /// The safe top is included only as the other measured edge, never as a guess.
    static func measuredStatusClusterMaxY(statusBarMaxY: CGFloat?, safeTop: CGFloat) -> CGFloat? {
        guard let statusBarMaxY, statusBarMaxY > 1 else { return nil }
        let bottom = max(statusBarMaxY, safeTop)
        return bottom > 1 ? bottom : nil
    }

    static func resolve(_ metrics: SideColumnChromeMetrics) -> SideColumnChromePlacement {
        if metrics.isTransitioning { return .pending }
        guard let bar = metrics.tabBarFrame, bar.width > 1, bar.height > 1 else { return .pending }
        if isSideTabBar(bar) {
            return resolveBesideSideTab(metrics, bar: bar)
        }
        return .toolbar
    }

    /// Side tab: the capsule shares that column's midX.
    private static func resolveBesideSideTab(
        _ metrics: SideColumnChromeMetrics,
        bar: CGRect
    ) -> SideColumnChromePlacement {
        // The platter frame is already in window coordinates. RTL does not mirror it.
        _ = metrics.layoutDirection
        guard metrics.buttonCount > 0 else {
            return .sideColumn(stackFrame: .zero, below: false)
        }
        guard let statusBottom = metrics.statusClusterMaxY, statusBottom >= 0 else { return .toolbar }
        let x = bar.midX - GlassTokens.toolbarControlCircleSide / 2
        // No clock on the cover. The punch hole occupies the top of this column,
        // and the system already drops the icon pill below it. Sit on that pill.
        let frame = statusBottom <= 1
            ? frameAboveIcons(metrics: metrics, x: x, bar: bar)
            : stackFrame(metrics: metrics, x: x, statusBottom: statusBottom)
        return accept(frame, metrics: metrics, bar: bar)
    }

    /// The pair rests one gap above the icon pill.
    private static func frameAboveIcons(metrics: SideColumnChromeMetrics, x: CGFloat, bar: CGRect) -> CGRect {
        let side = GlassTokens.toolbarControlCircleSide
        let height = side * CGFloat(metrics.buttonCount)
        return CGRect(
            x: x,
            y: bar.minY - GlassTokens.sideColumnChromeGap - height,
            width: side,
            height: height
        )
    }

    private static func stackFrame(metrics: SideColumnChromeMetrics, x: CGFloat, statusBottom: CGFloat) -> CGRect {
        let side = GlassTokens.toolbarControlCircleSide
        return CGRect(
            x: x,
            y: statusBottom + GlassTokens.sideColumnChromeGap,
            width: side,
            height: side * CGFloat(metrics.buttonCount)
        )
    }

    private static func accept(
        _ frame: CGRect,
        metrics: SideColumnChromeMetrics,
        bar: CGRect
    ) -> SideColumnChromePlacement {
        let gap = GlassTokens.sideColumnChromeGap
        let camera = cameraRegion(windowSize: metrics.windowSize, safeInsets: metrics.safeInsets, column: bar)
        let clearsTab = frame.maxY + gap <= bar.minY + 0.5 && !frame.intersects(bar)
        if clearsTab, fits(frame, in: metrics.windowSize, avoiding: camera) {
            return .sideColumn(stackFrame: frame, below: false)
        }
        return .toolbar
    }

    /// Sensor band at the top of the column. The landscape side inset is the tab
    /// column itself, so it is not a camera and must not push the pair back to the toolbar.
    static func cameraRegion(windowSize: CGSize, safeInsets: UIEdgeInsets, column: CGRect) -> CGRect {
        guard windowSize.width > 1, windowSize.height > 1, column.width > 1 else { return .zero }
        let top = safeInsets.top
        guard top > 20 else { return .zero }
        let onLeft = column.midX < windowSize.width * 0.5
        let x = onLeft ? 0 : windowSize.width - top
        return CGRect(x: x, y: 0, width: top, height: top)
    }

    static func isSideTabBar(_ frame: CGRect) -> Bool {
        frame.width >= 44 && frame.height > 80 && frame.height > frame.width * 1.4
    }

    private static func fits(_ frame: CGRect, in window: CGSize, avoiding camera: CGRect) -> Bool {
        frame.minY >= 0
            && frame.maxY <= window.height
            && frame.minX >= 0
            && frame.maxX <= window.width
            && !frame.intersects(camera)
    }
}

/// One measurement of the tab platter. Toolbar items and the side-column overlay both read it.
@MainActor
@Observable
final class SideColumnChromeState {
    static let shared = SideColumnChromeState()

    private(set) var isTransitioning = false
    /// False while a cover hides the tab root. The overlay is off, so the toolbar keeps the pair.
    private(set) var rootClear = true
    /// Places and categories on the Duo side column. Back sits under the bell instead of beside it.
    private(set) var showsSettingsDetailBack = false
    private var settingsDetailBackAction: (@MainActor () -> Void)?
    private(set) var windowSize: CGSize = .zero
    private(set) var safeInsets: UIEdgeInsets = .zero
    private(set) var tabBarFrame: CGRect?
    /// Visible glass pill of a side tab. Nil for a bottom tab or before it is found.
    private(set) var sidePillFrame: CGRect?
    private(set) var layoutDirection: LayoutDirection = .leftToRight
    private(set) var statusClusterMaxY: CGFloat?

    func beginTransition() {
        isTransitioning = true
    }

    func endTransition() {
        isTransitioning = false
    }

    func setRootClear(_ clear: Bool) {
        guard rootClear != clear else { return }
        rootClear = clear
    }

    func claimSettingsDetailBack(_ action: @escaping @MainActor () -> Void) {
        settingsDetailBackAction = action
        showsSettingsDetailBack = true
    }

    func releaseSettingsDetailBack() {
        settingsDetailBackAction = nil
        showsSettingsDetailBack = false
    }

    func performSettingsDetailBack() {
        settingsDetailBackAction?()
    }

    func update(
        windowSize: CGSize,
        safeInsets: UIEdgeInsets,
        tabBarFrame: CGRect?,
        sidePillFrame: CGRect? = nil,
        layoutDirection: LayoutDirection,
        statusClusterMaxY: CGFloat?
    ) {
        if self.windowSize != windowSize { self.windowSize = windowSize }
        if self.safeInsets != safeInsets { self.safeInsets = safeInsets }
        if !sameFrame(self.tabBarFrame, tabBarFrame) { self.tabBarFrame = tabBarFrame }
        if !sameFrame(self.sidePillFrame, sidePillFrame) { self.sidePillFrame = sidePillFrame }
        if self.layoutDirection != layoutDirection { self.layoutDirection = layoutDirection }
        if self.statusClusterMaxY != statusClusterMaxY { self.statusClusterMaxY = statusClusterMaxY }
    }

    private func sameFrame(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.minX - rhs.minX) < 0.5
                && abs(lhs.minY - rhs.minY) < 0.5
                && abs(lhs.width - rhs.width) < 0.5
                && abs(lhs.height - rhs.height) < 0.5
        default:
            return false
        }
    }

    func placement(buttonCount: Int) -> SideColumnChromePlacement {
        SideColumnChromeResolver.resolve(
            SideColumnChromeMetrics(
                windowSize: windowSize,
                safeInsets: safeInsets,
                tabBarFrame: tabBarFrame,
                layoutDirection: layoutDirection,
                buttonCount: buttonCount,
                isTransitioning: isTransitioning,
                statusClusterMaxY: statusClusterMaxY
            )
        )
    }

    /// How many hits the Trips capsule reserves. The landscape book stacks bell, plus, and merge.
    func duoCapsuleButtonCount(tripsTab: Bool, splitPair: Bool, singleTrailing: Bool) -> Int {
        guard tripsTab else { return 1 }
        if splitPair { return 3 }
        return singleTrailing ? 2 : 1
    }

    /// Duo only, and only while the tab bar is a vertical column. The stack shares
    /// that column, above the icons. A bottom tab keeps the horizontal toolbar pair.
    /// iPad stays in the toolbar. The full stack has to fit, so the bell does not
    /// jump to a spot the Trips actions cannot stand.
    func uprightDuoCapsuleFrame(buttonCount: Int, layout: MilehoundLayoutSnapshot) -> CGRect? {
        guard layout.layoutClass != .pad else { return nil }
        guard buttonCount > 0 else { return nil }
        let required = (layout.layoutClass == .duoOpen && layout.isLandscape) ? 3 : 2
        guard case .sideColumn = placement(buttonCount: max(buttonCount, required)) else { return nil }
        guard case .sideColumn(let frame, _) = placement(buttonCount: buttonCount) else { return nil }
        guard frame.width > 1, frame.height > 1 else { return nil }
        return frame
    }

    /// Pending keeps the toolbar copy. Hiding both is how the buttons vanished.
    var showsToolbarChrome: Bool {
        switch placement(buttonCount: 1) {
        case .toolbar, .pending:
            return true
        case .sideColumn:
            return false
        }
    }
}
