import SwiftUI
import UIKit

// MARK: - Class

/// Screen class. Device model names are not stored.
enum TrailhoundLayoutClass: String, Equatable, Sendable {
    /// iPhone portrait and closed fold portrait. Existing single column.
    case phone
    /// iPhone landscape and closed fold landscape (compact vertical size class).
    case phoneLandscape
    /// Phone-family device with both size classes regular (open inner screen).
    case duoOpen
    /// iPad. Narrow Split View / Slide Over resolves to `phone`.
    case pad
}

enum TripDetailStyle: Equatable, Sendable {
    case overlay
    case split
    case floatingPanel
    case stacked
}

enum RecordingCardArrangement: Equatable, Sendable {
    case list
    case pane
    case banner
}

enum SettingsChrome: Equatable, Sendable {
    case form
    case split
}

enum MapChrome: Equatable, Sendable {
    case bottomSheet
    case floatingTrailing
    case splitPane
}

enum TripDetailRegion: Equatable, Sendable {
    case automatic
    case details
    case map
}

struct TrailhoundLayoutSnapshot: Equatable, Sendable {
    var layoutClass: TrailhoundLayoutClass
    var size: CGSize
    var isLandscape: Bool

    static let phone = TrailhoundLayoutSnapshot(
        layoutClass: .phone,
        size: CGSize(width: 390, height: 844),
        isLandscape: false
    )

    var columnCount: Int {
        TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: contentWidth)
    }

    var contentWidth: CGFloat {
        switch layoutClass {
        case .duoOpen where isLandscape:
            return max(0, (size.width - GlassTokens.hingeGutter) / 2)
        case .phoneLandscape:
            return size.width * (1 - GlassTokens.railWidthFraction)
        case .pad where isLandscape:
            return size.width * (1 - GlassTokens.railWidthFraction)
        default:
            return size.width
        }
    }

    /// Landscape phone wider than the closed Duo cover and narrower than the open fold.
    /// Column shares match the fully flat book. Trips and the recording card stay half
    /// the content, because that book keeps them on the hinge. There is no hinge here.
    var isPhoneBook: Bool {
        layoutClass == .phoneLandscape
            && size.width >= TrailhoundLayoutResolver.phoneBookMinWidth
            && size.width < TrailhoundLayoutResolver.openFoldSpan
    }

    var splitsTrips: Bool {
        switch layoutClass {
        case .phone:
            return false
        case .phoneLandscape:
            return true
        case .duoOpen:
            return isLandscape
        case .pad:
            return isLandscape
        }
    }

    var opensTripInPane: Bool { layoutClass != .phone }

    var embedsTripDetail: Bool { layoutClass != .phone }

    var tripDetailStyle: TripDetailStyle {
        switch layoutClass {
        case .phone:
            return .overlay
        case .duoOpen:
            return isLandscape ? .split : .overlay
        case .phoneLandscape:
            return isPhoneBook ? .split : .floatingPanel
        case .pad:
            return isLandscape ? .floatingPanel : .stacked
        }
    }

    var recordingCardArrangement: RecordingCardArrangement {
        if isPhoneBook { return .pane }
        switch layoutClass {
        case .phone, .phoneLandscape:
            return .list
        case .duoOpen where !isLandscape:
            return .list
        default:
            return .pane
        }
    }

    /// Open fold held upright: the hinge runs across the middle. The recording card is centered in the top half.
    var pinsRecordingCardToFold: Bool {
        layoutClass == .duoOpen && !isLandscape
    }

    /// Recording uses a side-by-side pane. Closed landscape keeps the card in the scrolling list.
    var splitsRecording: Bool {
        switch layoutClass {
        case .duoOpen:
            return isLandscape
        case .pad:
            return true
        case .phoneLandscape:
            return isPhoneBook
        case .phone:
            return false
        }
    }

    /// Open book, and a wide landscape phone: the recording card takes the leading half, the trip list the trailing half.
    var recordingCardLeads: Bool {
        usesBookPanes
    }

    /// Idle Trips on the leading half, Travels on the trailing half.
    /// The open book is the widest fold. A compact height size class can still label that
    /// window phone landscape, so the fold span decides the closed cover. A phone wider
    /// than that cover uses the same two panes. A narrower phone landscape stays one list.
    var splitsIdleLibrary: Bool {
        if layoutClass == .pad { return true }
        guard isLandscape else { return false }
        if layoutClass == .duoOpen || isPhoneBook { return true }
        return size.width >= TrailhoundLayoutResolver.openFoldSpan
    }

    /// Inbox list beside the selected notice. The open book, a wide landscape phone,
    /// and iPad in both orientations. A phone and the closed cover stay one list.
    var usesSplitInbox: Bool {
        switch layoutClass {
        case .duoOpen, .pad:
            return true
        case .phoneLandscape:
            return isPhoneBook
        case .phone:
            return false
        }
    }

    /// Landscape phone and the open book share wide-book chrome.
    /// Width is not gated: the side tab shrinks the measured window under the fold span.
    var isWideBook: Bool {
        if layoutClass == .phoneLandscape { return true }
        if layoutClass == .duoOpen, isLandscape { return true }
        return false
    }

    /// Closed Duo cover, and the upright open fold when it is still shorter than a phone.
    /// The welcome column centers in that height instead of running off the top and bottom.
    var centersOnboardingColumn: Bool {
        if layoutClass == .duoOpen, !isLandscape { return true }
        guard layoutClass == .phone, size.width > 1 else { return false }
        return size.height / size.width < 1.75
    }

    /// Upright bottom sheet beside a side tab. The leading gap matches the margin
    /// between the card and the tab, not the width of the tab column.
    /// A normal phone has no trailing tab inset, so the sheet stays full-bleed.
    func duoSheetLeadingInset(matchingTrailingSafeArea trailing: CGFloat) -> CGFloat {
        guard tripDetailStyle == .overlay else { return 0 }
        guard trailing >= 44 else { return 0 }
        return GlassTokens.panelHorizontalInset
    }

    /// Phone and Duo put the camera and status cluster in the trailing corner.
    /// Full-screen collapse circles lead the title there. iPad keeps them trailing.
    var pinsOverlayCloseLeading: Bool {
        layoutClass != .pad
    }

    var hidesRecordingCardFromList: Bool {
        recordingCardArrangement == .pane || pinsRecordingCardToFold
    }

    var mapChrome: MapChrome {
        switch layoutClass {
        case .phone:
            return .bottomSheet
        case .duoOpen:
            return isLandscape ? .splitPane : .bottomSheet
        case .phoneLandscape:
            return isPhoneBook ? .splitPane : .floatingTrailing
        case .pad:
            return .floatingTrailing
        }
    }

    var settingsChrome: SettingsChrome {
        switch layoutClass {
        case .phone:
            return .form
        case .phoneLandscape:
            if isPhoneBook || size.width >= TrailhoundLayoutResolver.openFoldSpan {
                return .split
            }
            return .form
        case .duoOpen:
            return isLandscape ? .split : .form
        case .pad:
            return .split
        }
    }

    var badgeColumnCount: Int {
        TrailhoundLayoutResolver.badgeColumnCount(
            layout: isPhoneBook ? .duoOpen : layoutClass,
            isLandscape: isLandscape,
            accessibility: false
        )
    }

    var showsHeroRail: Bool {
        layoutClass == .phoneLandscape || (layoutClass == .pad && isLandscape)
    }

    /// Open book, a wide landscape phone, and iPad in both orientations. Closed cover landscape,
    /// including its widest span, stays the portrait list so shortcuts and saved vehicles use the width.
    var showsPairingVehicleFocus: Bool {
        switch layoutClass {
        case .pad:
            return true
        case .duoOpen:
            return isLandscape
        case .phoneLandscape:
            return isLandscape && isPhoneBook
        case .phone:
            return false
        }
    }

    /// Open Duo in landscape. The off-hinge 60/40 split also requires the hinge to be fully open.
    var isOpenBookLandscape: Bool {
        layoutClass == .duoOpen && isLandscape
    }

    /// Open Duo landscape, or a wide iPhone landscape that uses the same panes.
    var usesBookPanes: Bool { isOpenBookLandscape || isPhoneBook }

    /// iPad landscape. Same column shares as the fully flat book. There is no hinge.
    var isPadBook: Bool { layoutClass == .pad && isLandscape }

    /// Open Duo landscape, a wide iPhone landscape, or iPad landscape.
    var usesWidePanes: Bool { usesBookPanes || isPadBook }

    /// Upright Duo and iPad portrait, including iPad mini. Recap hubs share the row.
    /// The year-recap story stays full width under them. Landscape books keep the hinge stack.
    var packsPortraitRecapHalves: Bool {
        guard !isLandscape else { return false }
        switch layoutClass {
        case .duoOpen, .pad:
            return true
        case .phone, .phoneLandscape:
            return false
        }
    }

    /// 9:16 column on an open Duo and iPad. Nil on a phone: the story cover locks
    /// the phone to portrait, so a sideways phone does not lay the story out wide.
    /// The story view centers this column on the window. The side-tab inset must not leave it leading.
    var storyStageMaxWidth: CGFloat? {
        switch layoutClass {
        case .phone:
            return nil
        case .phoneLandscape, .duoOpen, .pad:
            return min(size.height * 9 / 16, size.width * 0.46)
        }
    }

    func hingeFrame() -> CGRect {
        TrailhoundLayoutResolver.hingeFrame(in: size, gutter: GlassTokens.hingeGutter)
    }
}

/// Trailing gap between a full-bleed container and the window edge: the side-tab column.
@MainActor
enum TrailhoundSideTabGap {
    static func trailing(in geometry: GeometryProxy, layoutDirection: LayoutDirection) -> CGFloat {
        let safe = geometry.safeAreaInsets.trailing
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let window else { return safe }
        let frame = geometry.frame(in: .global)
        let measured: CGFloat
        if frame.width > 1, frame.height > 1 {
            let raw = layoutDirection == .rightToLeft
                ? frame.minX
                : window.bounds.width - frame.maxX
            measured = raw > 0 && raw < frame.width ? raw : 0
        } else {
            measured = 0
        }
        let windowEdge = layoutDirection == .rightToLeft ? window.safeAreaInsets.left : window.safeAreaInsets.right
        return max(safe, windowEdge, measured, sideColumnWidth(in: window))
    }

    /// Vertical tab bar width. A bottom bar is wide and short, so it returns 0.
    private static func sideColumnWidth(in window: UIWindow) -> CGFloat {
        guard let bar = findTabBar(in: window) else { return 0 }
        guard bar.bounds.height > bar.bounds.width * 1.4, bar.bounds.width >= 44 else { return 0 }
        return bar.bounds.width
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for child in view.subviews {
            if let found = findTabBar(in: child) { return found }
        }
        return nil
    }
}

enum TrailhoundLayoutResolver {
    /// Open inner screen when a size class stays compact: the long side is two phones.
    static let openFoldSpan: CGFloat = 1100

    /// Landscape phones wider than the closed Duo cover use the open-book panes.
    /// The cover is about 678 pt. The open fold span stays the upper bound, so that cover keeps one column.
    static let phoneBookMinWidth: CGFloat = 700

    /// Vehicles list share of the content on the fully flat widest book. The focus pane is the rest.
    static let flatVehicleListFraction: CGFloat = 0.6

    /// Vehicle profile share on that same book. Tracking and expenses take the rest.
    static let flatVehicleProfileFraction: CGFloat = 0.4

    /// Statistics, Recap, and Settings leading column on the fully open hinge. The trailing column is the rest.
    static let flatStatsLeadingFraction: CGFloat = 0.45

    /// Settings section list on that same book. The form takes the rest.
    static let flatSettingsLeadingFraction: CGFloat = 0.4

    /// iPad portrait Settings. The section list is 30% of the content; the form is the rest.
    static let flatPadPortraitSettingsLeadingFraction: CGFloat = 0.3

    /// Vehicles panes leave the hinge only when the Duo is landscape and the hinge is fully open.
    /// A partially open hinge keeps the seam on the fold. iPad and phones have no such hinge.
    /// A wide landscape phone uses `flatBookLeadingFraction` instead: the same shares, with no hinge.
    static func usesOffHingeVehicleSplit(
        layoutClass: TrailhoundLayoutClass,
        isLandscape: Bool,
        hingeFullyOpen: Bool
    ) -> Bool {
        layoutClass == .duoOpen && isLandscape && hingeFullyOpen
    }

    /// Fully flat column share. A wide landscape phone and iPad landscape always use it.
    /// A Duo uses it only when the hinge is fully open; a partial fold stays on the hinge and returns nil.
    static func flatBookLeadingFraction(
        isPhoneBook: Bool,
        layoutClass: TrailhoundLayoutClass,
        isLandscape: Bool,
        hingeFullyOpen: Bool,
        fraction: CGFloat,
        isPadBook: Bool = false
    ) -> CGFloat? {
        if isPhoneBook || isPadBook { return fraction }
        guard usesOffHingeVehicleSplit(
            layoutClass: layoutClass,
            isLandscape: isLandscape,
            hingeFullyOpen: hingeFullyOpen
        ) else { return nil }
        return fraction
    }

    /// Settings leading share. iPad portrait is 30/70. Landscape iPad stays on the window midpoint.
    static func settingsLeadingFraction(
        isPhoneBook: Bool,
        layoutClass: TrailhoundLayoutClass,
        isLandscape: Bool,
        hingeFullyOpen: Bool
    ) -> CGFloat? {
        if layoutClass == .pad, !isLandscape {
            return flatPadPortraitSettingsLeadingFraction
        }
        return flatBookLeadingFraction(
            isPhoneBook: isPhoneBook,
            layoutClass: layoutClass,
            isLandscape: isLandscape,
            hingeFullyOpen: hingeFullyOpen,
            fraction: flatSettingsLeadingFraction,
            isPadBook: false
        )
    }

    /// A camera write while the window is turning cancels the orientation change.
    /// A sheet only changes height. A turn flips the aspect, or moves both axes together.
    static func viewportChangeCancelsRotation(from old: CGSize, to new: CGSize) -> Bool {
        guard old.width > 1, old.height > 1, new.width > 1, new.height > 1 else { return false }
        let widthDelta = abs(new.width - old.width)
        let heightDelta = abs(new.height - old.height)
        if aspectFlips(from: old, to: new) { return true }
        return widthDelta > 12 && heightDelta > 12
    }

    /// Portrait to landscape, or the reverse. The first frame of that resize is what
    /// cancels the Duo turn when the page rebuilds before UIKit has started it.
    static func aspectFlips(from old: CGSize, to new: CGSize) -> Bool {
        guard old.width > 1, old.height > 1, new.width > 1, new.height > 1 else { return false }
        return (old.width > old.height) != (new.width > new.height)
    }

    static func resolve(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        size: CGSize,
        idiom: UIUserInterfaceIdiom,
        debugOverride: TrailhoundLayoutClass? = nil
    ) -> TrailhoundLayoutClass {
        if let override = debugOverride ?? TrailhoundLayoutDebug.forcedClass {
            return override
        }
        let narrow = size.width > 0 && size.width < GlassTokens.compactWidthCeiling
        if idiom == .pad {
            if horizontal == .compact || narrow {
                return .phone
            }
            return .pad
        }
        if vertical == .compact {
            return .phoneLandscape
        }
        // Open inner screen. Portrait is often under 700pt wide, and some folds keep a
        // compact horizontal size class while the height is two phones stacked.
        if horizontal == .regular, vertical == .regular {
            return .duoOpen
        }
        if size.height >= openFoldSpan, size.height > size.width {
            return .duoOpen
        }
        if size.width >= openFoldSpan, size.width > size.height {
            return .duoOpen
        }
        return .phone
    }

    /// The key window, not a 390×844 stand-in. An open Duo's first SwiftUI pass
    /// often reports a phone-sized content rect; the window bounds are the fold.
    @MainActor
    static func currentWindowSize(fallback: CGSize) -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let windows = scene.windows
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                let bounds = window.bounds.size
                if bounds.width > 1, bounds.height > 1 { return bounds }
            }
        }
        return fallback
    }

    static func snapshot(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        size: CGSize,
        idiom: UIUserInterfaceIdiom
    ) -> TrailhoundLayoutSnapshot {
        let resolved = resolve(
            horizontal: horizontal,
            vertical: vertical,
            size: size,
            idiom: idiom
        )
        let landscape = size.width > size.height && size.height > 0
        return TrailhoundLayoutSnapshot(
            layoutClass: resolved,
            size: size,
            isLandscape: landscape
        )
    }

    /// The root keeps this snapshot while the window is turning.
    /// A slight-open fold jumps from the outer portrait to the inner landscape.
    /// Swapping the hierarchy in that turn cancels the orientation change and
    /// leaves the interface rotated.
    static func snapshotDuringTurn(
        presented: TrailhoundLayoutSnapshot,
        live: TrailhoundLayoutSnapshot,
        isRotating: Bool
    ) -> TrailhoundLayoutSnapshot {
        isRotating ? presented : live
    }

    /// Half tiles stay between `moduleMinHalf` and `moduleMaxHalf`. Extra width adds a column.
    static func columnCount(layout: TrailhoundLayoutClass, contentWidth: CGFloat) -> Int {
        let width = max(contentWidth, 1)
        var columns: Int
        switch layout {
        case .phone, .phoneLandscape, .duoOpen:
            columns = 2
        case .pad:
            columns = 4
        }
        while columns < 8, halfWidth(columns: columns, contentWidth: width) > GlassTokens.moduleMaxHalf {
            columns += 1
        }
        while columns > 1, halfWidth(columns: columns, contentWidth: width) < GlassTokens.moduleMinHalf {
            columns -= 1
        }
        return columns
    }

    static func halfWidth(columns: Int, contentWidth: CGFloat) -> CGFloat {
        let count = max(columns, 1)
        let gaps = StatsCardTokens.pairSpacing * CGFloat(count - 1)
        return (contentWidth - gaps) / CGFloat(count)
    }

    static func badgeColumnCount(
        layout: TrailhoundLayoutClass,
        isLandscape: Bool,
        accessibility: Bool
    ) -> Int {
        if accessibility { return 1 }
        switch layout {
        case .phone:
            return 2
        case .phoneLandscape:
            return 4
        case .duoOpen:
            return isLandscape ? 4 : 3
        case .pad:
            return isLandscape ? 6 : 4
        }
    }

    static func hingeFrame(in size: CGSize, gutter: CGFloat = GlassTokens.hingeGutter) -> CGRect {
        let width = min(gutter, size.width)
        let x = (size.width - width) / 2
        return CGRect(x: x, y: 0, width: width, height: size.height)
    }

    static func frameIntersectsHinge(_ frame: CGRect, container: CGSize, gutter: CGFloat = GlassTokens.hingeGutter) -> Bool {
        frame.intersects(hingeFrame(in: container, gutter: gutter))
    }

    /// List stays on the leading edge. Right-to-left mirrors it onto the visual right.
    static func listIsOnVisualLeft(direction: LayoutDirection) -> Bool {
        direction == .leftToRight
    }

    /// Width of the leading pane so the gutter sits on the window midpoint (the fold).
    /// A trailing tab column makes the content narrower than the window; splitting that
    /// content in half lands the seam off the hinge.
    static func duoLeadingPaneWidth(
        contentOriginX: CGFloat,
        contentWidth: CGFloat,
        windowWidth: CGFloat,
        gutter: CGFloat,
        listOnVisualLeft: Bool
    ) -> CGFloat {
        let fallback = max(0, (contentWidth - gutter) / 2)
        guard windowWidth > 1, contentWidth > 1 else { return fallback }
        let hinge = windowWidth / 2
        let halfGutter = gutter / 2
        let raw = listOnVisualLeft
            ? hinge - halfGutter - contentOriginX
            : (contentOriginX + contentWidth) - (hinge + halfGutter)
        guard raw > 0, raw < contentWidth else { return fallback }
        let minimum = min(160, fallback)
        let maximum = max(minimum, contentWidth - gutter - minimum)
        return min(max(raw, minimum), maximum)
    }

    /// Leading pane as a share of the content, with the gutter between the panes.
    /// Used when the fully flat book does not need the seam on the hinge.
    static func fractionLeadingPaneWidth(
        contentWidth: CGFloat,
        gutter: CGFloat,
        leadingFraction: CGFloat
    ) -> CGFloat {
        let usable = max(0, contentWidth - gutter)
        let fraction = min(max(leadingFraction, 0), 1)
        let raw = usable * fraction
        let minimum = min(160, usable / 2)
        let maximum = max(minimum, usable - minimum)
        return min(max(raw, minimum), maximum)
    }
}

enum TrailhoundWindowSpace {
    static let name = "trailhound.window"
}

/// The tab column is a safe-area inset. SwiftUI’s named-space width is the
/// inset content, so a 50/50 split lands beside the fold and the system white
/// background shows through on the other screen. This reads the content rect
/// in the UIKit window, whose midpoint is the hinge.
struct TrailhoundWindowFrameReader: UIViewRepresentable {
    var onChange: (CGRect, CGSize) -> Void

    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        uiView.onLayout = { [weak coordinator] frame, windowSize in
            coordinator?.publish(frame: frame, windowSize: windowSize)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    final class Probe: UIView {
        var onLayout: ((CGRect, CGSize) -> Void)?
        private var pending: (CGRect, CGSize)?
        private var coalesce: DispatchWorkItem?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let frame = convert(bounds, to: window)
            let windowSize = window.bounds.size
            guard frame.width > 1, frame.height > 1, windowSize.width > 1, windowSize.height > 1 else { return }
            pending = (frame, windowSize)
            coalesce?.cancel()
            // Fold and rotate layout every frame. Writing SwiftUI state from here
            // restarts the reflow spring and never lets the next tab draw.
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.onLayout?(pending.0, pending.1)
            }
            coalesce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    final class Coordinator {
        var onChange: (CGRect, CGSize) -> Void
        private var lastFrame: CGRect = .null
        private var lastWindowSize: CGSize = CGSize(width: -1, height: -1)

        init(onChange: @escaping (CGRect, CGSize) -> Void) {
            self.onChange = onChange
        }

        func publish(frame: CGRect, windowSize: CGSize) {
            let moved = abs(frame.minX - lastFrame.minX) > 2
                || abs(frame.minY - lastFrame.minY) > 2
                || abs(frame.width - lastFrame.width) > 2
                || abs(frame.height - lastFrame.height) > 2
                || abs(windowSize.width - lastWindowSize.width) > 2
                || abs(windowSize.height - lastWindowSize.height) > 2
            guard moved else { return }
            lastFrame = frame
            lastWindowSize = windowSize
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onChange(frame, windowSize)
            }
        }
    }
}

enum TrailhoundLayoutDebug {
    static var forcedClass: TrailhoundLayoutClass? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "trailhound.layout.debugClass") else {
            return nil
        }
        return TrailhoundLayoutClass(rawValue: raw)
        #else
        return nil
        #endif
    }
}

// MARK: - Environment

private struct TrailhoundLayoutKey: EnvironmentKey {
    static let defaultValue = TrailhoundLayoutSnapshot.phone
}

private struct TripDetailRegionKey: EnvironmentKey {
    static let defaultValue = TripDetailRegion.automatic
}

private struct FoldPaneHeaderBottomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var trailhoundLayout: TrailhoundLayoutSnapshot {
        get { self[TrailhoundLayoutKey.self] }
        set { self[TrailhoundLayoutKey.self] = newValue }
    }

    /// Bottom of the title bar, in the coordinates of a fold pane that bleeds up to the window top.
    /// Zero when the pane does not bleed.
    var foldPaneHeaderBottom: CGFloat {
        get { self[FoldPaneHeaderBottomKey.self] }
        set { self[FoldPaneHeaderBottomKey.self] = newValue }
    }

    var tripDetailRegion: TripDetailRegion {
        get { self[TripDetailRegionKey.self] }
        set { self[TripDetailRegionKey.self] = newValue }
    }
}

// MARK: - Module grid

enum TrailhoundModuleSpan: Hashable {
    case full
    case half
    case feature
}

private struct TrailhoundModuleSpanKey: LayoutValueKey {
    static let defaultValue = TrailhoundModuleSpan.full
}

extension View {
    func moduleSpan(_ span: TrailhoundModuleSpan) -> some View {
        layoutValue(key: TrailhoundModuleSpanKey.self, value: span)
    }

    /// Centers a card at the pane max width. The glass surface itself does not stretch.
    func trailhoundPaneCard() -> some View {
        frame(maxWidth: GlassTokens.paneCardMaxWidth)
            .frame(maxWidth: .infinity)
    }

    func trailhoundReadableColumn() -> some View {
        frame(maxWidth: GlassTokens.readableTextWidth)
            .frame(maxWidth: .infinity)
    }
}

struct TrailhoundModuleGridCache {
    var columns: Int
    var width: CGFloat
}

struct TrailhoundModuleGrid: Layout {
    var layoutClass: TrailhoundLayoutClass
    var spacing: CGFloat = StatsCardTokens.pairSpacing

    func makeCache(subviews: Subviews) -> TrailhoundModuleGridCache {
        TrailhoundModuleGridCache(columns: 2, width: 0)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TrailhoundModuleGridCache
    ) -> CGSize {
        let width = proposal.width ?? cache.width
        let columns = TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: width)
        cache = TrailhoundModuleGridCache(columns: columns, width: width)
        let frames = frames(for: subviews, width: width, columns: columns)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TrailhoundModuleGridCache
    ) {
        let columns = cache.width == bounds.width
            ? cache.columns
            : TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: bounds.width)
        let frames = frames(for: subviews, width: bounds.width, columns: columns)
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat, columns: Int) -> [CGRect] {
        let count = max(columns, 1)
        let cell = TrailhoundLayoutResolver.halfWidth(columns: count, contentWidth: width)
        var frames: [CGRect] = []
        var column = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowStart = 0

        func closeRow() {
            guard rowStart < frames.count else { return }
            for index in rowStart..<frames.count {
                frames[index].size.height = rowHeight
            }
            y += rowHeight
            column = 0
            rowHeight = 0
            rowStart = frames.count
        }

        for subview in subviews {
            let span = subview[TrailhoundModuleSpanKey.self]
            let need: Int
            switch span {
            case .half:
                need = 1
            case .full:
                need = count
            case .feature:
                need = min(2, count)
            }
            if column > 0, column + need > count {
                y += spacing
                closeRow()
            }
            let itemWidth = cell * CGFloat(need) + spacing * CGFloat(max(need - 1, 0))
            let measured = subview.sizeThatFits(
                ProposedViewSize(width: itemWidth, height: span == .feature ? GlassTokens.featureHeight : nil)
            ).height
            let height = span == .feature ? max(measured, GlassTokens.featureHeight) : measured
            let x = CGFloat(column) * (cell + spacing)
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: height))
            rowHeight = max(rowHeight, height)
            column += need
            if column >= count {
                closeRow()
            }
        }
        if column > 0 {
            closeRow()
        }
        return frames
    }
}

// MARK: - Hero, split, map

struct TrailhoundHeroRail<Title: View, Figure: View, Detail: View>: View {
    var collapsed: Bool
    @ViewBuilder var title: () -> Title
    @ViewBuilder var figure: () -> Figure
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title()
                .font(.subheadline.weight(.semibold))
                .glassSecondaryInk()
            if collapsed {
                figure()
                    .font(.title3.weight(.semibold))
                    .glassPrimaryInk()
                    .lineLimit(1)
            } else {
                figure()
                    .font(GlassTokens.heroFigureFont)
                    .glassPrimaryInk()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                detail()
                    .font(.subheadline)
                    .glassSecondaryInk()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Open-fold Recap. Two columns meet on the hinge. Each next card drops into the
/// shorter column so a short card does not leave a hole beside a taller one.
struct TrailhoundHingeMasonry: Layout {
    var leadingWidth: CGFloat?
    var columnGap: CGFloat = GlassTokens.hingeGutter
    var rowSpacing: CGFloat = StatsCardTokens.pairSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let frames = frames(for: subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, width: bounds.width)
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        let lead = resolvedLeading(width: width)
        let trail = max(0, width - columnGap - lead)
        let widths = [lead, trail]
        let origins = [CGFloat(0), lead + columnGap]
        var cursor = [CGFloat(0), CGFloat(0)]
        var frames: [CGRect] = []
        for subview in subviews {
            let column = cursor[0] <= cursor[1] ? 0 : 1
            let size = subview.sizeThatFits(ProposedViewSize(width: widths[column], height: nil))
            frames.append(CGRect(x: origins[column], y: cursor[column], width: widths[column], height: size.height))
            cursor[column] += size.height + rowSpacing
        }
        return frames
    }

    private func resolvedLeading(width: CGFloat) -> CGFloat {
        let fallback = max(0, (width - columnGap) / 2)
        guard let leadingWidth, leadingWidth > 1 else { return fallback }
        return min(max(leadingWidth, 1), max(width - columnGap - 1, 1))
    }
}

/// Measures the row in the window and packs `TrailhoundHingeMasonry` onto the fold.
struct TrailhoundHingeCardStack<Content: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @ViewBuilder var content: () -> Content

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowWidth: CGFloat = 0

    var body: some View {
        TrailhoundHingeMasonry(leadingWidth: leadingWidth) {
            content()
        }
        .statsCardListRow()
        .background {
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize.width != measuredWindowWidth else { return }
                contentInWindow = frame
                measuredWindowWidth = windowSize.width
            }
        }
    }

    private var leadingWidth: CGFloat? {
        let contentWidth = contentInWindow.width > 1 ? contentInWindow.width : layout.size.width
        guard contentWidth > 1 else { return nil }
        if let fraction = TrailhoundLayoutResolver.flatBookLeadingFraction(
            isPhoneBook: layout.isPhoneBook,
            layoutClass: layout.layoutClass,
            isLandscape: layout.isLandscape,
            hingeFullyOpen: TrailhoundHingeMonitor.shared.isFullyOpen,
            fraction: TrailhoundLayoutResolver.flatStatsLeadingFraction,
            isPadBook: layout.isPadBook
        ) {
            return TrailhoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: contentWidth,
                gutter: GlassTokens.hingeGutter,
                leadingFraction: fraction
            )
        }
        let windowWidth = measuredWindowWidth > 1 ? measuredWindowWidth : layout.size.width
        let origin = contentInWindow.width > 1 ? contentInWindow.minX : 0
        guard windowWidth > 1 else { return nil }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: origin,
            contentWidth: contentWidth,
            windowWidth: windowWidth,
            gutter: GlassTokens.hingeGutter,
            listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection)
        )
    }
}

/// Device rotation. The recording road must not redraw through UIKit's rotation
/// snapshot, and the trips page must not crossfade a second copy of itself.
@MainActor
@Observable
final class TrailhoundInterfaceRotation {
    static let shared = TrailhoundInterfaceRotation()

    private(set) var depth = 0
    /// SwiftUI often reports the new window size before UIKit starts the turn.
    /// Holding here keeps the page that is on screen until that turn ends.
    private var sizeHold = false
    private var holdToken = 0
    /// True through the frame that applies the layout the turn released.
    /// A spring on that frame fades the old page over the new one.
    private(set) var suppressReflowAnimation = false
    /// Display-link callback reads this without hopping to the main actor.
    nonisolated(unsafe) static var pausesRoadAnimation = false
    private var lastOrientationRepair: CFTimeInterval = 0

    var isRotating: Bool { depth > 0 || sizeHold }

    /// Call before publishing a size whose aspect flipped. UIKit's transition
    /// adopts the hold; if no transition arrives, the hold releases itself.
    func holdForIncomingTurn() {
        guard !sizeHold else { return }
        sizeHold = true
        Self.pausesRoadAnimation = true
        suppressReflowAnimation = true
        scheduleHoldRelease(after: .milliseconds(900))
    }

    func begin() {
        depth += 1
        sizeHold = true
        Self.pausesRoadAnimation = true
        suppressReflowAnimation = true
        // The geometry hold has a short timeout. A real turn outlives that, so
        // retire the timeout and let end() release the page. If end() never
        // arrives, drop the hold so portrait is not left off.
        holdToken += 1
        let token = holdToken
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            guard self.holdToken == token else { return }
            self.depth = 0
            self.releaseHold()
        }
    }

    func end() {
        depth = max(0, depth - 1)
        Self.pausesRoadAnimation = depth > 0 || sizeHold
        guard depth == 0 else { return }
        releaseHold()
    }

    /// One repair per stuck turn. A second request inside the cooldown fights the gesture.
    func shouldRepairOrientation() -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastOrientationRepair > 1.5 else { return false }
        lastOrientationRepair = now
        return true
    }

    private func scheduleHoldRelease(after delay: Duration) {
        holdToken += 1
        let token = holdToken
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard self.holdToken == token, self.depth == 0 else { return }
            self.releaseHold()
        }
    }

    private func releaseHold() {
        holdToken += 1
        sizeHold = false
        Self.pausesRoadAnimation = depth > 0
        suppressReflowAnimation = true
        Task { @MainActor in
            // Stay quiet through the frames after the turn. A spring in that
            // window fades the trip list over the open trip.
            try? await Task.sleep(for: .milliseconds(500))
            guard !self.isRotating else { return }
            self.suppressReflowAnimation = false
        }
    }
}

/// Where the recording card and the trip list sit while the window turns.
/// `stackAmount` is 0 side by side and 1 stacked. In between, the two panes slide
/// so a rotation is one move instead of two translucent screens.
enum RecordingAxisPlacement {
    struct Frames: Equatable {
        var live: CGRect
        var list: CGRect
    }

    /// Fully side by side once the window is this much wider than it is tall.
    static let sideBySideRatio: CGFloat = 1.12

    static func stackAmount(width: CGFloat, height: CGFloat) -> CGFloat {
        guard width > 1, height > 1 else { return 0 }
        let ratio = width / height
        let stacked = 1 / sideBySideRatio
        return min(1, max(0, (sideBySideRatio - ratio) / (sideBySideRatio - stacked)))
    }

    static func frames(
        in bounds: CGRect,
        gutter: CGFloat,
        liveLeads: Bool,
        listOnVisualLeft: Bool,
        contentInWindow: CGRect,
        windowSize: CGSize,
        evenSplit: Bool = false,
        forceSideBySide: Bool = false,
        forceStacked: Bool = false
    ) -> Frames {
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1 else {
            return Frames(live: bounds, list: bounds)
        }
        let gap = max(0, gutter)
        let travel: CGFloat = if forceSideBySide {
            0
        } else if forceStacked {
            1
        } else {
            stackAmount(width: width, height: height)
        }
        let landscape = landscapeFrames(
            in: bounds,
            gap: gap,
            liveLeads: liveLeads,
            listOnVisualLeft: listOnVisualLeft,
            contentInWindow: contentInWindow,
            windowSize: windowSize,
            evenSplit: evenSplit
        )
        let portrait = portraitFrames(
            in: bounds,
            gap: gap,
            contentInWindow: contentInWindow,
            windowSize: windowSize
        )
        return Frames(
            live: lerp(landscape.live, portrait.live, travel),
            list: lerp(landscape.list, portrait.list, travel)
        )
    }

    private static func landscapeFrames(
        in bounds: CGRect,
        gap: CGFloat,
        liveLeads: Bool,
        listOnVisualLeft: Bool,
        contentInWindow: CGRect,
        windowSize: CGSize,
        evenSplit: Bool
    ) -> Frames {
        let width = bounds.width
        let height = bounds.height
        let contentWidth = contentInWindow.width > 1 ? contentInWindow.width : width
        let originX = contentInWindow.width > 1 ? contentInWindow.minX : 0
        let windowWidth = windowSize.width > 1 ? windowSize.width : width
        let leading = evenSplit
            ? TrailhoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: width,
                gutter: gap,
                leadingFraction: 0.5
            )
            : TrailhoundLayoutResolver.duoLeadingPaneWidth(
                contentOriginX: originX,
                contentWidth: contentWidth,
                windowWidth: windowWidth,
                gutter: gap,
                listOnVisualLeft: listOnVisualLeft
            )
        let leadingWidth = min(max(0, leading), max(0, width - gap))
        let visualLeftWidth = listOnVisualLeft
            ? leadingWidth
            : max(0, width - gap - leadingWidth)
        let visualRightWidth = max(0, width - gap - visualLeftWidth)
        let left = CGRect(x: bounds.minX, y: bounds.minY, width: visualLeftWidth, height: height)
        let right = CGRect(
            x: bounds.minX + visualLeftWidth + gap,
            y: bounds.minY,
            width: visualRightWidth,
            height: height
        )
        let liveOnVisualLeft = liveLeads == listOnVisualLeft
        return Frames(
            live: liveOnVisualLeft ? left : right,
            list: liveOnVisualLeft ? right : left
        )
    }

    private static func portraitFrames(
        in bounds: CGRect,
        gap: CGFloat,
        contentInWindow: CGRect,
        windowSize: CGSize
    ) -> Frames {
        let width = bounds.width
        let height = bounds.height
        let contentHeight = contentInWindow.height > 1 ? contentInWindow.height : height
        let originY = contentInWindow.height > 1 ? contentInWindow.minY : 0
        let windowHeight = windowSize.height > 1 ? windowSize.height : height
        let topSpan = TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: originY,
            contentWidth: contentHeight,
            windowWidth: windowHeight,
            gutter: gap,
            listOnVisualLeft: true
        )
        let topHeight = min(max(0, topSpan), max(0, height - gap))
        let bottomHeight = max(0, height - gap - topHeight)
        return Frames(
            live: CGRect(x: bounds.minX, y: bounds.minY, width: width, height: topHeight),
            list: CGRect(
                x: bounds.minX,
                y: bounds.minY + topHeight + gap,
                width: width,
                height: bottomHeight
            )
        )
    }

    private static func lerp(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * t,
            y: from.minY + (to.minY - from.minY) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }
}

/// Recording card and trip list. The same two children slide between a side-by-side
/// book and a stacked fold, so a turn does not fade a second copy of the page.
struct RecordingAxisLayout: Layout {
    var gutter: CGFloat
    var liveLeads: Bool
    var listOnVisualLeft: Bool
    var contentInWindow: CGRect
    var windowSize: CGSize
    var evenSplit: Bool
    /// iPad portrait stays two columns. A tall window must not stack the card across the screen.
    var forceSideBySide: Bool = false
    /// Settled upright fold. A tall top safe area shortens the pane below the
    /// stacking ratio, and the blend then shifts the card left and the list right.
    var forceStacked: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let frames = RecordingAxisPlacement.frames(
            in: bounds,
            gutter: gutter,
            liveLeads: liveLeads,
            listOnVisualLeft: listOnVisualLeft,
            contentInWindow: contentInWindow,
            windowSize: windowSize,
            evenSplit: evenSplit,
            forceSideBySide: forceSideBySide,
            forceStacked: forceStacked
        )
        subviews[0].place(
            at: frames.live.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(frames.live.size)
        )
        subviews[1].place(
            at: frames.list.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(frames.list.size)
        )
    }
}

struct RecordingOrientationStage<Live: View, List: View>: View {
    var gutter: CGFloat
    var liveLeads: Bool
    @ViewBuilder var live: () -> Live
    @ViewBuilder var list: () -> List

    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindow: CGSize = .zero

    var body: some View {
        RecordingAxisLayout(
            gutter: gutter,
            liveLeads: liveLeads,
            listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection),
            contentInWindow: contentInWindow,
            windowSize: measuredWindow,
            evenSplit: layout.isPhoneBook,
            forceSideBySide: layout.layoutClass == .pad,
            forceStacked: layout.pinsRecordingCardToFold
                && !TrailhoundInterfaceRotation.shared.isRotating
        ) {
            live()
                .clipped()
            list()
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AtmosphericBackground()
                .ignoresSafeArea()
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize != measuredWindow else { return }
                contentInWindow = frame
                measuredWindow = windowSize
            }
        }
    }
}

/// Idle Trips | Travels book. `splitAmount` is 0 for one column and 1 side by side.
/// The trailing library fades while both columns still have their landscape width,
/// then the leading list widens. Nothing scales, so a turn is not a shrink and a pop.
enum LibraryAxisPlacement {
    struct Frames: Equatable {
        var trips: CGRect
        var travels: CGRect
    }

    /// Fully one column at a square window. Fully side by side once the window is a
    /// landscape book — including an iPad whose side tab makes the content a little narrower.
    static let splitStartRatio: CGFloat = 1
    static let splitEndRatio: CGFloat = 1.18
    /// Trailing library is gone before the leading column leaves its half.
    static let fadeCutoff: CGFloat = 0.62

    static func splitAmount(width: CGFloat, height: CGFloat, requiresBookSpan: Bool = true) -> CGFloat {
        guard width > 1, height > 1 else { return 0 }
        if requiresBookSpan, max(width, height) < TrailhoundLayoutResolver.openFoldSpan { return 0 }
        let span = splitEndRatio - splitStartRatio
        guard span > 0 else { return 0 }
        let t = (width / height - splitStartRatio) / span
        return smooth(t)
    }

    /// 1 while the trailing library is still fading. Then eases toward the full-width column.
    static func frameSplit(_ split: CGFloat) -> CGFloat {
        guard split < fadeCutoff else { return 1 }
        guard fadeCutoff > 0 else { return 0 }
        return smooth(split / fadeCutoff)
    }

    static func travelsOpacity(_ split: CGFloat) -> CGFloat {
        guard split > fadeCutoff else { return 0 }
        return smooth((split - fadeCutoff) / (1 - fadeCutoff))
    }

    /// Leading list drops the Trips | Travels segment once the window is leaving the single column.
    static func pinsTripsLibrary(_ split: CGFloat) -> Bool {
        split > 0.04
    }

    static func frames(
        in bounds: CGRect,
        gutter: CGFloat,
        frameSplit: CGFloat,
        listOnVisualLeft: Bool,
        contentInWindow: CGRect,
        windowSize: CGSize,
        evenSplit: Bool = false
    ) -> Frames {
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1 else {
            return Frames(trips: bounds, travels: bounds)
        }
        let sideBySide = sideBySideFrames(
            in: bounds,
            gap: max(0, gutter),
            listOnVisualLeft: listOnVisualLeft,
            contentInWindow: contentInWindow,
            windowSize: windowSize,
            evenSplit: evenSplit
        )
        let full = CGRect(x: bounds.minX, y: bounds.minY, width: width, height: height)
        return Frames(
            trips: lerp(full, sideBySide.trips, frameSplit),
            travels: sideBySide.travels
        )
    }

    private static func sideBySideFrames(
        in bounds: CGRect,
        gap: CGFloat,
        listOnVisualLeft: Bool,
        contentInWindow: CGRect,
        windowSize: CGSize,
        evenSplit: Bool
    ) -> Frames {
        let width = bounds.width
        let height = bounds.height
        let contentWidth = contentInWindow.width > 1 ? contentInWindow.width : width
        let originX = contentInWindow.width > 1 ? contentInWindow.minX : 0
        let windowWidth = windowSize.width > 1 ? windowSize.width : width
        let leading = evenSplit
            ? TrailhoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: width,
                gutter: gap,
                leadingFraction: 0.5
            )
            : TrailhoundLayoutResolver.duoLeadingPaneWidth(
                contentOriginX: originX,
                contentWidth: contentWidth,
                windowWidth: windowWidth,
                gutter: gap,
                listOnVisualLeft: listOnVisualLeft
            )
        let leadingWidth = min(max(0, leading), max(0, width - gap))
        let visualLeftWidth = listOnVisualLeft
            ? leadingWidth
            : max(0, width - gap - leadingWidth)
        let visualRightWidth = max(0, width - gap - visualLeftWidth)
        let left = CGRect(x: bounds.minX, y: bounds.minY, width: visualLeftWidth, height: height)
        let right = CGRect(
            x: bounds.minX + visualLeftWidth + gap,
            y: bounds.minY,
            width: visualRightWidth,
            height: height
        )
        return Frames(
            trips: listOnVisualLeft ? left : right,
            travels: listOnVisualLeft ? right : left
        )
    }

    private static func lerp(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        let amount = min(1, max(0, t))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * amount,
            y: from.minY + (to.minY - from.minY) * amount,
            width: from.width + (to.width - from.width) * amount,
            height: from.height + (to.height - from.height) * amount
        )
    }

    private static func smooth(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}

/// Trips and Travels stay mounted. Frames follow the window, so a rotation does not
/// crossfade a second copy or scale the page.
struct LibraryAxisLayout: Layout {
    var gutter: CGFloat
    var frameSplit: CGFloat
    var listOnVisualLeft: Bool
    var contentInWindow: CGRect
    var windowSize: CGSize
    var evenSplit: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let frames = LibraryAxisPlacement.frames(
            in: bounds,
            gutter: gutter,
            frameSplit: frameSplit,
            listOnVisualLeft: listOnVisualLeft,
            contentInWindow: contentInWindow,
            windowSize: windowSize,
            evenSplit: evenSplit
        )
        subviews[0].place(
            at: frames.trips.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(frames.trips.size)
        )
        subviews[1].place(
            at: frames.travels.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(frames.travels.size)
        )
    }
}

struct LibraryOrientationStage<Trips: View, Travels: View>: View {
    var gutter: CGFloat
    var reduceMotion: Bool
    @ViewBuilder var trips: (CGFloat) -> Trips
    @ViewBuilder var travels: () -> Travels

    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindow: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let split = resolvedSplit(in: geo.size)
            let opacity = LibraryAxisPlacement.travelsOpacity(split)
            let slide = reduceMotion ? 0 : (1 - opacity) * 16
            let towardTrailing: CGFloat = TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection) ? 1 : -1
            LibraryAxisLayout(
                gutter: gutter,
                frameSplit: LibraryAxisPlacement.frameSplit(split),
                listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection),
                contentInWindow: contentInWindow,
                windowSize: measuredWindow == .zero ? geo.size : measuredWindow,
                evenSplit: layout.isPhoneBook
            ) {
                trips(split)
                    .clipped()
                travels()
                    .clipped()
                    .opacity(opacity)
                    .offset(x: towardTrailing * slide)
                    .animation(nil, value: opacity)
                    .allowsHitTesting(opacity > 0.2)
                    .accessibilityHidden(opacity == 0)
                    .disabled(opacity == 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .transaction { transaction in
                // The rotation already moves the bounds. A spring on top scales the columns.
                if reduceMotion || TrailhoundInterfaceRotation.shared.isRotating {
                    transaction.animation = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AtmosphericBackground()
                .ignoresSafeArea()
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize != measuredWindow else { return }
                contentInWindow = frame
                measuredWindow = windowSize
            }
        }
    }

    /// Reduce Motion snaps at the midpoint. The slide and the in-between widths stay off.
    /// The stage is only mounted on the open book, a wide landscape phone, and iPad, so a side-tab inset must
    /// not fail the phone-width gate and collapse a landscape book.
    private func resolvedSplit(in size: CGSize) -> CGFloat {
        if layout.layoutClass == .pad { return 1 }
        let live = LibraryAxisPlacement.splitAmount(
            width: size.width,
            height: size.height,
            requiresBookSpan: false
        )
        guard reduceMotion else { return live }
        return live > 0.5 ? 1 : 0
    }
}

/// Leading pane is the list. Focus is the live surface. Right-to-left mirrors the stack.
/// The gutter is centered on the window, not on the tab-inset content, so it sits on the fold.
struct TrailhoundPaneSplit<Leading: View, Focus: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    var gutter: CGFloat?
    /// Share of the content for the leading pane. Nil keeps the gutter on the hinge.
    var leadingFraction: CGFloat?
    /// Live map column. It covers the vertical safe area so the shell blue does not show above and below the map.
    var leadingFillsVertically: Bool = false
    var focusFillsVertically: Bool = false
    /// Focus pane draws under the side tab. The hinge gutter stays put; only the trailing screen edge is covered.
    var focusBleedsTrailing: Bool = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var focus: () -> Focus

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowWidth: CGFloat = 0

    var body: some View {
        let gap = gutter ?? defaultGutter
        bleedTrailing(split(gap: gap, leadingWidth: leadingWidth(gap: gap)))
            .background {
                AtmosphericBackground()
                    .ignoresSafeArea()
                TrailhoundWindowFrameReader { frame, windowSize in
                    guard frame != contentInWindow || windowSize.width != measuredWindowWidth else { return }
                    contentInWindow = frame
                    measuredWindowWidth = windowSize.width
                }
            }
    }

    private func leadingWidth(gap: CGFloat) -> CGFloat? {
        let contentWidth = contentInWindow.width
        guard contentWidth > 1 else { return nil }
        if let leadingFraction {
            return TrailhoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: contentWidth,
                gutter: gap,
                leadingFraction: leadingFraction
            )
        }
        if layout.isPhoneBook {
            return TrailhoundLayoutResolver.fractionLeadingPaneWidth(
                contentWidth: contentWidth,
                gutter: gap,
                leadingFraction: 0.5
            )
        }
        let windowWidth = measuredWindowWidth > 1 ? measuredWindowWidth : layout.size.width
        let origin = contentInWindow.minX
        guard windowWidth > 1 else { return nil }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: origin,
            contentWidth: contentWidth,
            windowWidth: windowWidth,
            gutter: gap,
            listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection)
        )
    }

    private func split(gap: CGFloat, leadingWidth: CGFloat?) -> some View {
        HStack(spacing: gap) {
            pane(leading(), width: leadingWidth, fillsVertically: leadingFillsVertically)
            pane(focus(), width: nil, fillsVertically: focusFillsVertically)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func bleedTrailing<Content: View>(_ content: Content) -> some View {
        if focusBleedsTrailing {
            content.ignoresSafeArea(edges: .trailing)
        } else {
            content
        }
    }

    private func pane<Content: View>(_ content: Content, width: CGFloat?, fillsVertically: Bool) -> some View {
        let framed = content
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity)
        return Group {
            if fillsVertically {
                framed.ignoresSafeArea(edges: .vertical)
            } else {
                framed.clipShape(Rectangle())
            }
        }
    }

    private var defaultGutter: CGFloat {
        if layout.layoutClass == .pad, layout.isLandscape {
            return GlassTokens.padLandscapeGap
        }
        if layout.layoutClass == .duoOpen {
            return GlassTokens.hingeGutter
        }
        return GlassTokens.hingeGutter
    }
}

/// Portrait open fold. The top pane ends on the horizontal hinge; the list fills below it.
struct TrailhoundFoldStack<Top: View, Bottom: View>: View {
    var gutter: CGFloat = GlassTokens.hingeGutter
    /// Live map. The pane is the top half of the window: it draws under the status
    /// band and its bottom edge sits on the horizontal hinge.
    var topFillsToEdge: Bool = false
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    @Environment(\.trailhoundLayout) private var layout
    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowHeight: CGFloat = 0
    @State private var safeTop: CGFloat = 0

    var body: some View {
        VStack(spacing: gutter) {
            topPane
            bottom()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AtmosphericBackground()
                .ignoresSafeArea()
            GeometryReader { geo in
                Color.clear
                    .onAppear { safeTop = geo.safeAreaInsets.top }
                    .onChange(of: geo.safeAreaInsets.top) { _, top in
                        safeTop = top
                    }
            }
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize.height != measuredWindowHeight else { return }
                contentInWindow = frame
                measuredWindowHeight = windowSize.height
            }
        }
    }

    private var topPane: some View {
        let bleed = topFillsToEdge ? max(0, contentInWindow.minY) : 0
        let framed = top()
            .environment(\.foldPaneHeaderBottom, bleed)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .frame(height: topHeight.map { $0 + bleed })
            .padding(.top, -bleed)
        return Group {
            if topFillsToEdge {
                framed
            } else {
                framed.clipShape(Rectangle())
            }
        }
    }

    /// The fold's top in the window. A missing nav-bar inset reports a tiny minY
    /// while the title still occupies `safeTop`, which parks the card under the title.
    private var contentTop: CGFloat {
        max(contentInWindow.minY, safeTop)
    }

    /// Layout height from the content top to the hinge. `topFillsToEdge` adds the
    /// top bleed back in the frame, then pulls it up, so the bottom stays on the fold.
    private var topHeight: CGFloat? {
        if let measured = measuredTopHeight { return measured }
        guard layout.pinsRecordingCardToFold, layout.size.height > 1 else { return nil }
        return max(1, layout.size.height / 2 - gutter / 2)
    }

    private var measuredTopHeight: CGFloat? {
        let contentHeight = contentInWindow.height
        let windowHeight = measuredWindowHeight
        guard contentHeight > 1, windowHeight > 1 else { return nil }
        if topFillsToEdge {
            let height = windowHeight / 2 - contentInWindow.minY
            return height > 1 ? height : nil
        }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: contentTop,
            contentWidth: contentHeight,
            windowWidth: windowHeight,
            gutter: gutter,
            listOnVisualLeft: true
        )
    }
}

struct TrailhoundMapCanvas<MapContent: View, Panel: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Binding var panelCollapsed: Bool
    @ViewBuilder var map: () -> MapContent
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        switch layout.mapChrome {
        case .bottomSheet:
            ZStack(alignment: .bottom) {
                map()
                panel()
            }
        case .floatingTrailing:
            ZStack(alignment: .trailing) {
                map()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !panelCollapsed {
                    panel()
                        .frame(width: GlassTokens.floatingPanelWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 16)
                        .padding(.vertical, 12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                VStack {
                    HStack {
                        Spacer()
                        GlassToolbarCollapseButton(
                            accessibilityIdentifier: "layout.map.panel.collapse",
                            action: { panelCollapsed.toggle() }
                        )
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                    }
                    Spacer()
                }
            }
        case .splitPane:
            TrailhoundPaneSplit {
                panel()
            } focus: {
                map()
            }
        }
    }
}

struct TrailhoundAdaptiveSheet: ViewModifier {
    @Environment(\.trailhoundLayout) private var layout

    func body(content: Content) -> some View {
        if layout.layoutClass == .pad {
            if #available(iOS 18.0, *) {
                content
                    .presentationSizing(.form)
                    .frame(maxWidth: 560)
            } else {
                content.frame(maxWidth: 560)
            }
        } else {
            content
        }
    }
}

extension View {
    func trailhoundAdaptiveSheet() -> some View {
        modifier(TrailhoundAdaptiveSheet())
    }
}

/// Fully open hinge versus a partially open fold. Vehicles uses this so the 60/40
/// split stays off the seam while the Duo is only slightly folded.
@MainActor
@Observable
final class TrailhoundHingeMonitor {
    static let shared = TrailhoundHingeMonitor()

    private(set) var isFullyOpen = false

    func setFullyOpen(_ open: Bool) {
        guard open != isFullyOpen else { return }
        isFullyOpen = open
    }
}

/// Sits in the window so UIKit can deliver hinge updates.
/// `UIHinge` exists only in the iOS 27.1 SDK. CI builds with Xcode 26.5, so the
/// interaction is installed from `TrailhoundSDKShims.m`, which compiles it out there.
struct TrailhoundHingeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        TrailhoundInstallHingeInteraction(view) { open in
            Task { @MainActor in
                TrailhoundHingeMonitor.shared.setFullyOpen(open)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
