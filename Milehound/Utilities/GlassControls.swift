import SwiftUI
import UIKit

private struct GlassControlSchemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark || shellPalette.usesLightChrome(for: colorScheme) {
            content
        } else {
            content.environment(\.colorScheme, .dark)
        }
    }
}

private struct GlassToggleTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .tint(GlassControlTint.toggle(for: colorScheme, palette: shellPalette))
            // Keep the system switch on the real Light/Dark chrome. A dark-scheme
            // switch on a light grouped row is a white pill with no track.
            .environment(\.colorScheme, colorScheme)
    }
}

struct GlassSectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GlassText.secondary(for: colorScheme))
            .textCase(.uppercase)
    }
}

struct GlassSectionFooter: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(GlassText.secondary(for: colorScheme))
    }
}

/// Theme-colored row disclosure. Light uses palette chrome so `>` reads on open glass.
struct GlassDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .glassDisclosureInk()
            .accessibilityHidden(true)
    }
}

/// How a nav-bar control draws its chrome.
///
/// - `system`: iOS 26 shared toolbar platter (Material bar item on iOS 18). Use
///   on form/list screens and Trip/Travel detail nav items.
/// - `frozen`: 36pt solid circle. Compact map chip if needed.
/// - `frozenControl`: 44pt solid circle if Reduce Transparency / frozen sampling is required.
enum GlassToolbarSampling {
    case system
    case frozen
    case frozenControl

    fileprivate var frozenCircleSide: CGFloat? {
        switch self {
        case .system: nil
        case .frozen: GlassTokens.toolbarFrozenCircleSide
        case .frozenControl: GlassTokens.toolbarControlCircleSide
        }
    }
}

/// Palette-tinted SF Symbol for the navigation bar.
struct GlassToolbarSymbol: View {
    let systemName: String
    var isLoading: Bool = false
    var sampling: GlassToolbarSampling = .system
    /// Wider glyphs (merge) sit smaller so the circle matches the bell.
    var pointSize: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.glassToolbarClustered) private var clustered

    var body: some View {
        glyph
            .modifier(GlassToolbarFrozenCircle(side: sampling.frozenCircleSide))
            .modifier(GlassToolbarSystemHitFill(enabled: sampling == .system, clustered: clustered))
    }

    @ViewBuilder
    private var glyph: some View {
        let tint = shellPalette.tintColor(for: colorScheme)
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(tint)
        } else {
            Image(systemName: systemName)
                .font(pointSize.map { Font.system(size: $0, weight: .semibold) } ?? .body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .tint(tint)
                // Map expand/collapse rides a 1.1–1.4s transaction. Default SF
                // Symbol replace interpolates this pair through unreadable frames
                // for the whole curve. Snap the glyph; keep the glass circle identity.
                .contentTransition(.identity)
                .transaction(value: systemName) { $0.animation = nil }
        }
    }
}

/// Inline navigation title without the iOS 26 glass header capsule.
/// Place with `ToolbarItem(placement: .title)` and hide the shared platter.
struct GlassToolbarNavTitle: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(shellPalette.tintColor(for: colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// `ToolbarItem(placement: .title)` plus hidden shared background.
struct GlassToolbarNavTitleItem: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .title) {
            GlassToolbarNavTitle(title: title)
        }
        .hideSharedToolbarBackgroundIfAvailable()
    }
}

/// Palette-tinted nav-bar title (Save / Cancel / Done). System path has no
/// custom capsule — the toolbar platter is the chrome.
struct GlassToolbarTitle: View {
    let title: String
    var sampling: GlassToolbarSampling = .system

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let tint = shellPalette.tintColor(for: colorScheme)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .tint(tint)
            .padding(.horizontal, 10)
            .frame(minHeight: GlassTokens.toolbarControlCircleSide)
            .contentShape(Capsule(style: .continuous))
            .modifier(GlassToolbarFrozenCapsule(enabled: sampling == .frozen))
    }
}

/// Adjacent trailing/leading actions share one toolbar platter (Trips merge+bell).
/// Do not copy Trips’ Start-alignment padding onto other screens.
///
/// - Parameter clustered: `true` when the items share the system glass platter.
///   Uses a tighter gap and narrower glyphs so the inline nav title can fit.
///   Leave `false` for independent 44pt circles (Trip detail, Year recap).
struct GlassToolbarCluster<Content: View>: View {
    var clustered: Bool = false
    private let content: Content

    init(clustered: Bool = false, @ViewBuilder content: () -> Content) {
        self.clustered = clustered
        self.content = content()
    }

    var body: some View {
        HStack(spacing: clustered ? GlassTokens.toolbarSharedClusterSpacing : GlassTokens.toolbarCircleClusterSpacing) {
            content
        }
        .environment(\.glassToolbarClustered, clustered)
    }
}

private struct GlassToolbarClusteredKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var glassToolbarClustered: Bool {
        get { self[GlassToolbarClusteredKey.self] }
        set { self[GlassToolbarClusteredKey.self] = newValue }
    }
}

/// Overlay toolbar circle (44pt). Year recap Share/Close, Stats collapse.
/// Liquid Glass — not the opaque frozen plate.
struct GlassNavCircleIcon: View {
    let systemName: String
    var isLoading: Bool = false
    var frozen: Bool = false
    var pointSize: CGFloat? = nil

    var body: some View {
        GlassToolbarSymbol(systemName: systemName, isLoading: isLoading, pointSize: pointSize)
            .glassCircleChrome(frozen: frozen)
            .contentShape(Circle())
    }
}

/// 44pt Liquid Glass circle whose **entire** chrome is the control — not the glyph.
/// Toolbar items that use this must hide the system shared platter
/// (`hideSharedToolbarBackgroundIfAvailable`) so MapKit cannot steal taps
/// in the glass that iOS draws outside the SwiftUI icon.
struct GlassToolbarCircleButton: View {
    let systemName: String
    var isLoading: Bool = false
    var frozen: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassNavCircleIcon(systemName: systemName, isLoading: isLoading, frozen: frozen)
        }
        .buttonStyle(.glassPlainHit)
        .contentShape(Circle())
    }
}

/// Collapse / exit-fullscreen: 44pt Liquid Glass circle (not a naked glyph).
struct GlassToolbarCollapseButton: View {
    var accessibilityIdentifier: String
    var frozen: Bool = false
    var action: () -> Void

    var body: some View {
        GlassToolbarCircleButton(
            systemName: "arrow.down.right.and.arrow.up.left",
            frozen: frozen,
            action: action
        )
        .accessibilityLabel(L10n.mapExitFullscreen)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// System toolbar glass is ~44pt; a bare SF Symbol is ~20pt. MapKit (and empty
/// space in the circle) swallows taps unless the SwiftUI control fills the chrome.
/// Shared-platter clusters keep the 44pt height but use a tighter width so the
/// inline title (Milehound) is not truncated by two 44pt glyphs.
private struct GlassToolbarSystemHitFill: ViewModifier {
    var enabled: Bool
    var clustered: Bool = false

    func body(content: Content) -> some View {
        if enabled {
            if clustered {
                content
                    .frame(
                        width: GlassTokens.toolbarClusterGlyphWidth,
                        height: GlassTokens.toolbarControlCircleSide,
                        alignment: .center
                    )
                    .contentShape(Rectangle())
            } else {
                content
                    .frame(
                        width: GlassTokens.toolbarControlCircleSide,
                        height: GlassTokens.toolbarControlCircleSide,
                        alignment: .center
                    )
                    .contentShape(Circle())
            }
        } else {
            content
        }
    }
}

private struct GlassToolbarFrozenCircle: ViewModifier {
    var side: CGFloat?

    func body(content: Content) -> some View {
        if let side {
            content
                .frame(width: side, height: side, alignment: .center)
                .background {
                    GlassToolbarFrozenPlate(shape: Circle())
                }
                .contentShape(Circle())
        } else {
            content
        }
    }
}

private struct GlassToolbarFrozenCapsule: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    GlassToolbarFrozenPlate(shape: Capsule(style: .continuous))
                }
                .contentShape(Capsule(style: .continuous))
        } else {
            content
        }
    }
}

extension View {
    /// Forces leaf system controls (DatePicker / menu Picker / TextField) to draw light labels
    /// on the colored shell without flipping Material sampling for ancestors.
    func glassControlScheme() -> some View {
        modifier(GlassControlSchemeModifier())
    }

    func glassToggleStyle() -> some View {
        modifier(GlassToggleTintModifier())
    }

    func glassTextField() -> some View {
        glassInputField()
            .glassControlScheme()
    }

    /// Compact DatePicker on glass — Light value is white (`glassControlScheme`).
    /// Open calendar keeps white numbers; selected day is a white disc, not blue, not black ink.
    func glassDatePicker() -> some View {
        modifier(GlassDatePickerModifier())
    }

    /// Menu Picker on glass — Light value + chevron stay white (system menu uses accent blue).
    /// Local `.tint` on the leaf control only; do not apply white tint at tab/toolbar chrome.
    func glassMenuPicker() -> some View {
        modifier(GlassMenuPickerModifier())
    }

    func glassStepper() -> some View {
        glassControlScheme()
            .modifier(GlassStepperTintModifier())
    }
}

extension ToolbarContent {
    /// Drops the iOS 26 system toolbar platter. Use when the item draws its own
    /// chrome (frozen map circles) or is a semantic opaque pill (`LocationPermissionBadge`).
    @ToolbarContentBuilder
    func hideSharedToolbarBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

private struct GlassDatePickerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .datePickerStyle(.compact)
            .buttonStyle(.plain)
            .glassControlScheme()
            .tint(GlassControlTint.datePickerCompact(for: colorScheme, palette: shellPalette))
            .background {
                GlassDatePickerUIKitBridge()
            }
    }
}

private struct GlassDatePickerUIKitBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> GlassDatePickerProbeView {
        let view = GlassDatePickerProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: GlassDatePickerProbeView, context: Context) {
        uiView.applySoon()
    }
}

final class GlassDatePickerProbeView: UIView {
    func applySoon() {
        GlassDatePickerChrome.installIfNeeded()
        apply()
        Task { @MainActor [weak self] in
            self?.apply()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    func apply() {
        if let window {
            GlassDatePickerChrome.apply(in: window)
        }
        var ancestor: UIView? = superview
        for _ in 0..<8 {
            guard let current = ancestor else { break }
            GlassDatePickerChrome.styleCompactPickers(in: current)
            ancestor = current.superview
        }
    }
}

@MainActor
enum GlassDatePickerChrome {
    static let selectedFill = UIColor.white
    static let selectedTitle = UIColor.white

    static func installIfNeeded() {
        guard !didInstallObserver else { return }
        didInstallObserver = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { note in
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let window = object as? UIWindow else { return }
                apply(in: window)
                Task { apply(in: window) }
                Task {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    apply(in: window)
                }
            }
        }
    }

    private static var didInstallObserver = false

    static func apply(in root: UIView) {
        if isDatePopoverHost(root) {
            stylePopoverTree(root)
            return
        }
        styleCompactPickers(in: root)
        if let window = root as? UIWindow {
            for subview in window.subviews where isDatePopoverHost(subview) {
                stylePopoverTree(subview)
            }
        }
    }

    static func styleCompactPickers(in root: UIView) {
        if let picker = root as? UIDatePicker {
            picker.tintColor = selectedFill
        }
        for child in root.subviews {
            styleCompactPickers(in: child)
        }
    }

    private static func stylePopoverTree(_ root: UIView) {
        let name = String(describing: type(of: root))
        let isCalendarHost = root is UICalendarView
            || name.contains("Calendar")
            || name.contains("DatePicker")
        if isCalendarHost {
            root.overrideUserInterfaceStyle = .dark
            root.tintColor = selectedFill
        }
        if let calendar = root as? UICalendarView {
            calendar.overrideUserInterfaceStyle = .dark
            calendar.tintColor = selectedFill
        }
        if let picker = root as? UIDatePicker {
            picker.overrideUserInterfaceStyle = .dark
            picker.tintColor = selectedFill
        }
        paintSelectedDay(in: root)
        root.subviews.forEach(stylePopoverTree)
    }

    private static func paintSelectedDay(in view: UIView) {
        if let cell = view as? UICollectionViewCell, cell.isSelected || cell.isHighlighted {
            paintSelectionChrome(cell)
        }
        if isCircularSelection(view) {
            replaceAccentFill(on: view)
        }
        if let label = view as? UILabel {
            label.textColor = selectedTitle
        }
        if let cell = view as? UICollectionViewCell, cell.isSelected {
            if var background = cell.backgroundConfiguration {
                background.backgroundColor = selectedFill.withAlphaComponent(0.35)
                cell.backgroundConfiguration = background
            }
            cell.selectedBackgroundView?.backgroundColor = selectedFill.withAlphaComponent(0.35)
            cell.selectedBackgroundView?.tintColor = selectedFill
        }
        view.subviews.forEach(paintSelectedDay)
    }

    private static func paintSelectionChrome(_ root: UIView) {
        replaceAccentFill(on: root)
        if isCircularSelection(root) {
            root.backgroundColor = selectedFill.withAlphaComponent(0.35)
            root.layer.backgroundColor = selectedFill.withAlphaComponent(0.35).cgColor
            root.layer.borderColor = selectedFill.cgColor
            root.layer.borderWidth = 1.5
        }
        if let label = root as? UILabel {
            label.textColor = selectedTitle
        }
        root.tintColor = selectedFill
        root.subviews.forEach(paintSelectionChrome)
    }

    private static func replaceAccentFill(on view: UIView) {
        if let fill = view.backgroundColor, isAccentBlue(fill) {
            view.backgroundColor = selectedFill.withAlphaComponent(0.35)
        }
        if let layerColor = view.layer.backgroundColor {
            let layerFill = UIColor(cgColor: layerColor)
            if isAccentBlue(layerFill) {
                view.layer.backgroundColor = selectedFill.withAlphaComponent(0.35).cgColor
            }
        }
    }

    private static func isDatePopoverHost(_ view: UIView) -> Bool {
        let name = String(describing: type(of: view))
        if name.contains("Keyboard") || name.contains("UITextEffects") || name.contains("Passcode") {
            return false
        }
        if view is UICalendarView
            || name.contains("DatePickerContainer")
            || name.contains("DatePickerCalendar")
            || name.contains("UICalendar") {
            return true
        }
        if let window = view as? UIWindow {
            if isFullScreen(window) { return false }
            return containsDatePickerChrome(window)
        }
        return name.contains("Popover") && containsDatePickerChrome(view)
    }

    private static func isFullScreen(_ window: UIWindow) -> Bool {
        let screen = window.screen.bounds.size
        let size = window.bounds.size
        return abs(size.width - screen.width) < 2 && abs(size.height - screen.height) < 2
    }

    private static func containsDatePickerChrome(_ root: UIView) -> Bool {
        if root is UICalendarView || root is UIDatePicker { return true }
        let name = String(describing: type(of: root))
        if name.contains("DatePicker") || name.contains("UICalendar") { return true }
        return root.subviews.contains { containsDatePickerChrome($0) }
    }

    private static func isCircularSelection(_ view: UIView) -> Bool {
        let size = view.bounds.size
        guard size.width >= 18, size.height >= 18, abs(size.width - size.height) < 6 else {
            return false
        }
        return view.layer.cornerRadius >= min(size.width, size.height) / 2 - 2
    }

    nonisolated static func isAccentBlue(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0.15 else {
            return false
        }
        return blue > 0.45 && blue > red + 0.08 && blue >= green
    }
}

private struct GlassMenuPickerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .glassControlScheme()
            .tint(GlassControlTint.control(for: colorScheme, palette: shellPalette))
    }
}

private struct GlassStepperTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.shellTint(for: colorScheme))
    }
}
