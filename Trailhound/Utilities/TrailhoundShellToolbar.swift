import SwiftData
import SwiftUI

/// Start (with the vehicle picker) and the notification bell on every tab root.
/// Start hides while a trip is already recording or paused.
struct TrailhoundShellToolbar: ViewModifier {
    var pageOwnsLeading: Bool = false
    /// Split book and merge mode draw the bell inside their own trailing item.
    /// A second `.topBarTrailing` item is what iOS parks beside the side tab;
    /// rotating that circle drops the bell glyph.
    var pageOwnsTrailing: Bool = false

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trailhoundLayout) private var layout
    @Query(sort: \VehicleProfile.name) private var vehicles: [VehicleProfile]
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var chrome = SideColumnChromeState.shared
    @State private var showsDrivingSafetyNotice = false

    func body(content: Content) -> some View {
        content.toolbar {
            if !pageOwnsLeading, showsStart {
                ToolbarItem(placement: .topBarLeading) {
                    startCluster
                }
            }
            if !pageOwnsTrailing, sideCapsuleFrame == nil || !chrome.rootClear {
                ToolbarItem(placement: .topBarTrailing) {
                    statusPair
                }
            }
        }
        .alert(L10n.drivingSafetyNoticeTitle, isPresented: $showsDrivingSafetyNotice) {
            Button(L10n.drivingSafetyNoticeConfirm) {
                DrivingSafetyNoticePolicy().markShown()
                startRecording()
            }
            .accessibilityIdentifier("drivingSafetyNotice.confirm")
        } message: {
            Text(L10n.drivingSafetyNoticeMessage)
        }
    }

    /// Open Duo when the stack fits under the Wi-Fi. The window overlay draws it.
    private var sideCapsuleFrame: CGRect? {
        chrome.uprightDuoCapsuleFrame(buttonCount: capsuleButtonCount, layout: layout)
    }

    private var capsuleButtonCount: Int {
        chrome.duoCapsuleButtonCount(
            tripsTab: tabSelection.selectedTab == .trips,
            splitPair: tabSelection.wideBookShowsPlusAndMerge,
            singleTrailing: showsTripsTrailing
        )
    }

    private var showsStart: Bool {
        !recordingService.state.isActiveSession
    }

    private var startCluster: some View {
        HStack(spacing: 4) {
            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(from: vehicles),
                    onSelect: { recordingService.setRecordingVehicle($0) }
                )
            }
            Button(action: startOrFocusRecording) {
                TrailhoundRunningHoundIcon(reduceMotion: reduceMotion)
            }
            .accessibilityLabel(L10n.string("action.start"))
            .accessibilityIdentifier("shell.start")
        }
    }

    /// Bell and the Trips action. Horizontal on the toolbar. The upright Duo overlay draws the vertical capsule.
    private var statusPair: some View {
        GlassToolbarCluster(clustered: true) {
            TrailhoundNotificationBell()
            if showsTripsTrailing {
                Button {
                    tabSelection.triggerWideBookTrailing()
                } label: {
                    GlassToolbarSymbol(
                        systemName: tabSelection.wideBookTrailingSymbol,
                        pointSize: tabSelection.wideBookTrailingSymbol == "plus" ? nil : 15
                    )
                }
                .accessibilityLabel(tabSelection.wideBookTrailingLabel)
                .accessibilityIdentifier(tripsTrailingIdentifier)
            }
        }
    }

    private var showsTripsTrailing: Bool {
        tabSelection.selectedTab == .trips && tabSelection.wideBookTrailingVisible
    }

    private var tripsTrailingIdentifier: String {
        tabSelection.wideBookTrailingSymbol == "plus"
            ? SideColumnChromeID.newJournal
            : SideColumnChromeID.merge
    }

    private func startOrFocusRecording() {
        TrailhoundHaptics.selection()
        if recordingService.state.isActiveSession {
            tabSelection.focusRecordingCard()
            return
        }
        if DrivingSafetyNoticePolicy().shouldShow {
            showsDrivingSafetyNotice = true
            return
        }
        startRecording()
    }

    private func startRecording() {
        tabSelection.openTrips()
        if recordingService.startManualRecording() {
            tabSelection.focusRecordingCard()
        }
    }
}

extension View {
    func trailhoundShellToolbar(pageOwnsLeading: Bool = false, pageOwnsTrailing: Bool = false) -> some View {
        modifier(TrailhoundShellToolbar(pageOwnsLeading: pageOwnsLeading, pageOwnsTrailing: pageOwnsTrailing))
    }
}

/// Bell, then the Trips action when that action is showing. One vertical Liquid Glass capsule.
struct DuoSideStatusCapsule: View {
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var chrome = SideColumnChromeState.shared

    private var showsTripsTrailing: Bool {
        tabSelection.selectedTab == .trips && tabSelection.wideBookTrailingVisible
    }

    /// Trips sets the split flag and leaves it set when another tab is picked.
    private var showsSplitPair: Bool {
        tabSelection.selectedTab == .trips && tabSelection.wideBookShowsPlusAndMerge
    }

    var body: some View {
        VStack(spacing: 0) {
            TrailhoundNotificationBell()
            if chrome.showsSettingsDetailBack {
                Button {
                    chrome.performSettingsDetailBack()
                } label: {
                    GlassToolbarSymbol(systemName: "chevron.backward")
                }
                .accessibilityLabel(Text("onboarding.back"))
                .accessibilityIdentifier("settings.places.back")
            }
            if showsSplitPair {
                splitAction(systemName: "plus", label: L10n.journalNew, identifier: SideColumnChromeID.newJournal) {
                    tabSelection.triggerNewJournal()
                }
                splitAction(systemName: "arrow.triangle.merge", label: L10n.actionMerge, identifier: SideColumnChromeID.merge, pointSize: 15) {
                    tabSelection.triggerMerge()
                }
            } else if showsTripsTrailing {
                splitAction(
                    systemName: tabSelection.wideBookTrailingSymbol,
                    label: tabSelection.wideBookTrailingLabel,
                    identifier: tripsTrailingIdentifier,
                    pointSize: tabSelection.wideBookTrailingSymbol == "plus" ? nil : 15
                ) {
                    tabSelection.triggerWideBookTrailing()
                }
            }
        }
        .buttonStyle(.glassPlainHit)
        .glassCapsuleChrome()
        .accessibilityElement(children: .contain)
    }

    private var tripsTrailingIdentifier: String {
        tabSelection.wideBookTrailingSymbol == "plus"
            ? SideColumnChromeID.newJournal
            : SideColumnChromeID.merge
    }

    private func splitAction(
        systemName: String,
        label: String,
        identifier: String,
        pointSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassToolbarSymbol(systemName: systemName, pointSize: pointSize)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// True while the selected tab is on its root and nothing is presented over it.
struct TabRootClearReader: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class Probe: UIView {
        var onChange: ((Bool) -> Void)?
        private var last: Bool?

        override init(frame: CGRect) {
            super.init(frame: frame)
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Probe, _) in
                view.last = nil
                view.report()
            }
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard let clear = Self.isClear(window) else { return }
            guard clear != last else { return }
            last = clear
            let onChange = onChange
            DispatchQueue.main.async {
                onChange?(clear)
            }
        }

        /// Nil while the probe has no window. A trait change drops the window for a
        /// frame; latching that as "covered" hid the capsule and the toolbar together.
        static func isClear(_ window: UIWindow?) -> Bool? {
            guard let window else { return nil }
            guard let root = window.rootViewController else { return false }
            if hasPresented(root) { return false }
            guard let navigation = navigationController(in: tabBarController(from: root)) else { return true }
            return navigation.viewControllers.count <= 1
        }

        private static func hasPresented(_ controller: UIViewController) -> Bool {
            if controller.presentedViewController != nil { return true }
            return controller.children.contains { hasPresented($0) }
        }

        private static func tabBarController(from controller: UIViewController) -> UITabBarController? {
            if let tab = controller as? UITabBarController { return tab }
            for child in controller.children {
                if let found = tabBarController(from: child) { return found }
            }
            return nil
        }

        private static func navigationController(in tab: UITabBarController?) -> UINavigationController? {
            guard let selected = tab?.selectedViewController else { return nil }
            return findNavigation(selected)
        }

        private static func findNavigation(_ controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            for child in controller.children {
                if let found = findNavigation(child) { return found }
            }
            return nil
        }
    }
}

/// `mainTabs` origin in window coordinates. The capsule frame uses that same space.
struct WindowOriginReader: UIViewRepresentable {
    var onChange: (CGPoint) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class Probe: UIView {
        var onChange: ((CGPoint) -> Void)?
        private var last: CGPoint?

        override init(frame: CGRect) {
            super.init(frame: frame)
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Probe, _) in
                view.last = nil
                view.report()
            }
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard let window else { return }
            let origin = convert(bounds, to: window).origin
            if let last, abs(last.x - origin.x) < 0.5, abs(last.y - origin.y) < 0.5 { return }
            last = origin
            let onChange = onChange
            DispatchQueue.main.async {
                onChange?(origin)
            }
        }
    }
}

/// Liquid Glass bell in the trailing toolbar capsule, beside merge.
struct TrailhoundNotificationBell: View {
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var notificationStore = AppNotificationStore.shared

    var body: some View {
        Button {
            notificationStore.markAllRead()
            tabSelection.openNotifications()
        } label: {
            GlassToolbarSymbol(systemName: "bell")
        }
        .accessibilityLabel(L10n.notificationsTitle)
        .accessibilityValue(notificationStore.unreadCount > 0 ? "\(min(notificationStore.unreadCount, 99))" : "")
        .accessibilityIdentifier(SideColumnChromeID.notifications)
        .overlay(alignment: .topTrailing) {
            if notificationStore.unreadCount > 0 {
                Text("\(min(notificationStore.unreadCount, 99))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, notificationStore.unreadCount > 9 ? 5 : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(GlassSemantic.notificationBadge, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    }
                    .scaleEffect(0.7)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
