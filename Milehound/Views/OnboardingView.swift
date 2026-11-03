import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case location
    case vehicleCare
    case shortcuts

    static var count: Int { allCases.count }
}

struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.milehoundLayout) private var layout
    @Bindable private var settings = AppSettings.shared

    @State private var page = OnboardingStep.welcome.rawValue
    @State private var showShortcutsAutomationGuide = false

    @State private var brandReveal: CGFloat = 0
    @State private var heroReveal: CGFloat = 0
    @State private var driveInProgress: CGFloat = 0
    @State private var beatProgress: CGFloat = 0
    @State private var detailsReveal: CGFloat = 0
    @State private var entranceToken = 0

    private var pageCount: Int { OnboardingStep.count }
    private var currentStep: OnboardingStep {
        OnboardingStep(rawValue: page) ?? .welcome
    }

    private var sceneIsLive: Bool {
        scenePhase == .active && heroReveal > 0.02
    }

    private var shortcutsGuideIsOpen: Bool {
        showShortcutsAutomationGuide
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(style: .canvas)

            Group {
                if layout.layoutClass == .phone || layout.centersOnboardingColumn {
                    portraitOnboarding
                } else if layout.layoutClass == .pad, !layout.isLandscape {
                    padPortraitOnboarding
                } else {
                    wideOnboarding
                }
            }
            .transaction { $0.disablesAnimations = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView()
                .milehoundAdaptiveSheet()
        }
        .task(id: entranceToken) {
            await Task.yield()
            await runEntrance(for: currentStep)
        }
        .onChange(of: page) { _, _ in
            prepareEntrance()
            entranceToken &+= 1
        }
    }

    private var onboardingPager: some View {
        TabView(selection: $page) {
            welcomePage
                .tag(OnboardingStep.welcome.rawValue)
            locationPage
                .tag(OnboardingStep.location.rawValue)
            vehicleCarePage
                .tag(OnboardingStep.vehicleCare.rawValue)
            shortcutsPage
                .tag(OnboardingStep.shortcuts.rawValue)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(MilehoundMotion.gentle, value: page)
    }

    private var portraitOnboarding: some View {
        VStack(spacing: 0) {
            onboardingPager
            pageIndicator
                .padding(.top, layout.centersOnboardingColumn ? 6 : 8)
            bottomBar
                .padding(.horizontal, layout.centersOnboardingColumn ? 20 : 24)
                .padding(.bottom, layout.centersOnboardingColumn ? 16 : 32)
                .opacity(detailsReveal)
                .offset(y: (1 - detailsReveal) * 12)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: layout.centersOnboardingColumn ? .center : .top
        )
    }

    private var padPortraitOnboarding: some View {
        VStack(spacing: 0) {
            onboardingPager
            pageIndicator
                .padding(.top, 8)
            bottomBar
                .milehoundReadableColumn()
                .padding(.bottom, 32)
                .opacity(detailsReveal)
        }
    }

    /// Landscape and open-fold slice: the scene sits beside the copy.
    private var usesWideOnboarding: Bool {
        if layout.layoutClass == .phone || layout.centersOnboardingColumn { return false }
        if layout.layoutClass == .pad, !layout.isLandscape { return false }
        return true
    }

    private var wideOnboarding: some View {
        let gap = layout.layoutClass == .pad ? GlassTokens.padLandscapeGap : GlassTokens.hingeGutter
        return GeometryReader { geo in
            let sceneWidth = wideSceneWidth(in: geo, gap: gap)
            HStack(spacing: gap) {
                onboardingSceneColumn
                    .scaleEffect(shrinksWideScene ? 0.82 : 1, anchor: .center)
                    .frame(width: sceneWidth)
                    .frame(maxHeight: .infinity)
                VStack(spacing: 10) {
                    onboardingPager
                    pageIndicator
                    bottomBar
                        .opacity(detailsReveal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Closed landscape keeps a narrower scene. Open book mode splits on the hinge.
    private var shrinksWideScene: Bool { layout.layoutClass == .phoneLandscape }

    /// Five columns for the scene, seven for the copy, when the fold is closed.
    /// Open book mode puts the seam on the window midpoint.
    /// The leading camera already sits in the scene side, so that inset comes out of the scene.
    private func wideSceneWidth(in geo: GeometryProxy, gap: CGFloat) -> CGFloat {
        let inner = max(geo.size.width - 32 - gap, 1)
        if layout.layoutClass == .pad {
            return inner * 0.36
        }
        let full = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        if layout.layoutClass == .duoOpen, layout.isLandscape {
            return MilehoundLayoutResolver.duoLeadingPaneWidth(
                contentOriginX: geo.safeAreaInsets.leading + 16,
                contentWidth: max(geo.size.width - 32, 1),
                windowWidth: full,
                gutter: gap,
                listOnVisualLeft: true
            )
        }
        let scene = full * 5 / 12 - geo.safeAreaInsets.leading - 16
        return min(max(scene, 120), inner * 0.46)
    }

    private var onboardingSceneColumn: some View {
        ZStack {
            if page == OnboardingStep.welcome.rawValue {
                MilehoundBrandMark(showsWordmark: true, symbolSize: 96)
                    .opacity(Double(brandReveal) * Double(1 - heroReveal))
                    .allowsHitTesting(false)
            }
            OnboardingHeroScene(
                kind: heroKind(for: currentStep),
                driveInProgress: driveInProgress,
                beatProgress: beatProgress,
                isAnimating: sceneIsLive && !shortcutsGuideIsOpen
            )
            .opacity(heroReveal)
        }
        .frame(height: MilehoundRoadSceneMetrics.hero.sceneHeight)
        .frame(maxHeight: .infinity)
    }

    private func heroKind(for step: OnboardingStep) -> OnboardingHeroKind {
        switch step {
        case .welcome: .welcomeDrive
        case .location: .locationPin
        case .vehicleCare: .vehicleCare
        case .shortcuts: .shortcutsLink
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        onboardingHeroPage(
            kind: .welcomeDrive,
            title: L10n.string("onboarding.welcome.title"),
            message: L10n.string("onboarding.welcome.message"),
            showsBrandColdOpen: true
        ) {
            VStack(alignment: .leading, spacing: featureSpacing) {
                onboardingFeatureRow(
                    icon: "point.topleft.down.curvedto.point.bottomright.up",
                    text: L10n.string("onboarding.features.routes")
                )
                onboardingFeatureRow(
                    icon: "chart.bar.fill",
                    text: L10n.string("onboarding.features.insights")
                )
                onboardingFeatureRow(
                    icon: "record.circle",
                    text: L10n.string("onboarding.features.recording")
                )
                onboardingFeatureRow(
                    icon: "bolt.horizontal.circle.fill",
                    text: L10n.string("onboarding.features.auto")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var locationPage: some View {
        onboardingHeroPage(
            kind: .locationPin,
            title: L10n.string("onboarding.location.title"),
            message: L10n.string("onboarding.location.message")
        ) {
            VStack(spacing: 12) {
                LocationPermissionBadge(state: locationService.authorizationState)

                locationPermissionActions
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var vehicleCarePage: some View {
        onboardingHeroPage(
            kind: .vehicleCare,
            title: L10n.string("onboarding.vehicle_care.title"),
            message: L10n.string("onboarding.vehicle_care.message")
        ) {
            VStack(alignment: .leading, spacing: featureSpacing) {
                onboardingFeatureRow(
                    icon: "calendar.badge.clock",
                    text: L10n.string("onboarding.vehicle_care.reminders")
                )
                onboardingFeatureRow(
                    icon: "creditcard.circle.fill",
                    text: L10n.string("onboarding.vehicle_care.expenses")
                )
                onboardingFeatureRow(
                    icon: "chart.pie.fill",
                    text: L10n.string("onboarding.vehicle_care.charts")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var shortcutsPage: some View {
        onboardingHeroPage(
            kind: .shortcutsLink,
            title: L10n.string("onboarding.shortcuts.title"),
            message: L10n.string("onboarding.shortcuts.message")
        ) {
            Button {
                showShortcutsAutomationGuide = true
                MilehoundHaptics.selection()
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.string("onboarding.shortcuts.link"))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .font(featureLinkFont)
            }
            .glassAccentForeground()
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Building blocks

    private func onboardingHeroPage<Extra: View>(
        kind: OnboardingHeroKind,
        title: String,
        message: String? = nil,
        showsBrandColdOpen: Bool = false,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        let column = onboardingHeroColumn(
            kind: kind,
            title: title,
            message: message,
            showsBrandColdOpen: showsBrandColdOpen,
            extra: extra
        )
        return Group {
            if layout.centersOnboardingColumn {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    column
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if showsBrandColdOpen {
                        MilehoundBrandMark(showsWordmark: true, symbolSize: 72)
                            .opacity(Double(brandReveal) * Double(1 - heroReveal))
                            .scaleEffect(0.92 + 0.08 * brandReveal)
                            .allowsHitTesting(false)
                    }
                }
            } else if usesWideOnboarding {
                WideOnboardingTextFit(content: column.padding(.horizontal, 4))
            } else {
                VStack(spacing: 22) {
                    Spacer(minLength: 12)
                    column
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: usesWideOnboarding ? .infinity : GlassTokens.readableTextWidth)
        .frame(maxWidth: .infinity)
    }

    private func onboardingHeroColumn<Extra: View>(
        kind: OnboardingHeroKind,
        title: String,
        message: String?,
        showsBrandColdOpen: Bool,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(spacing: usesWideOnboarding ? 6 : 22) {
            if showsInlineHero {
                ZStack {
                    if showsBrandColdOpen, !layout.centersOnboardingColumn {
                        MilehoundBrandMark(showsWordmark: true, symbolSize: 96)
                            .opacity(Double(brandReveal) * Double(1 - heroReveal))
                            .scaleEffect(0.92 + 0.08 * brandReveal)
                            .allowsHitTesting(false)
                    }

                    OnboardingHeroScene(
                        kind: kind,
                        driveInProgress: driveInProgress,
                        beatProgress: beatProgress,
                        isAnimating: sceneIsLive && page == stepRawValue(for: kind) && !shortcutsGuideIsOpen
                    )
                    .opacity(heroReveal)
                    .offset(y: (1 - heroReveal) * 18)
                    .scaleEffect(0.96 + 0.04 * heroReveal, anchor: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: MilehoundRoadSceneMetrics.hero.sceneHeight)
            }

            VStack(spacing: usesWideOnboarding ? 4 : 12) {
                Text(title)
                    .font(titleFont)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(messageFont)
                        .glassSecondaryInk()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .opacity(detailsReveal)
            .offset(y: (1 - detailsReveal) * 10)

            extra()
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(detailsReveal)
                .offset(y: (1 - detailsReveal) * 8)
        }
    }

    private func stepRawValue(for kind: OnboardingHeroKind) -> Int {
        switch kind {
        case .welcomeDrive: return OnboardingStep.welcome.rawValue
        case .locationPin: return OnboardingStep.location.rawValue
        case .vehicleCare: return OnboardingStep.vehicleCare.rawValue
        case .shortcutsLink: return OnboardingStep.shortcuts.rawValue
        }
    }

    private var showsInlineHero: Bool {
        layout.layoutClass == .phone
            || layout.centersOnboardingColumn
            || (layout.layoutClass == .pad && !layout.isLandscape)
    }

    private var titleFont: Font {
        if usesWideOnboarding { return .headline.bold() }
        if layout.centersOnboardingColumn { return .headline.bold() }
        return .title2.bold()
    }

    private var messageFont: Font {
        if usesWideOnboarding || layout.centersOnboardingColumn { return .footnote }
        return .body
    }

    private var featureFont: Font {
        if usesWideOnboarding || layout.centersOnboardingColumn { return .caption }
        return .subheadline
    }

    private var featureLinkFont: Font {
        if layout.centersOnboardingColumn { return .footnote.weight(.semibold) }
        if usesWideOnboarding { return .subheadline.weight(.semibold) }
        return .body.weight(.semibold)
    }

    private var featureSpacing: CGFloat { usesWideOnboarding ? 6 : 14 }

    private func onboardingFeatureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: usesWideOnboarding ? 8 : 12) {
            Image(systemName: icon)
                .font(.system(size: usesWideOnboarding ? 15 : 20, weight: .semibold))
                .glassAccentForeground()
                .frame(width: usesWideOnboarding ? 20 : 28, alignment: .center)

            Text(text)
                .font(featureFont)
                .lineSpacing(layout.centersOnboardingColumn ? 1 : 0)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private var locationPermissionActions: some View {
        switch locationService.authorizationState {
        case .authorizedAlways:
            Text(L10n.string("onboarding.permission.granted"))
                .font(layout.centersOnboardingColumn ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        case .denied, .restricted:
            Button(L10n.locationBannerSettings) {
                openAppSettings()
            }
            .milehoundProminentButton()
            .tint(MilehoundBrandColors.brandBottom)
        case .notDetermined, .authorizedWhenInUse:
            Button(L10n.string("onboarding.location.enable_always")) {
                locationService.requestPermission()
                MilehoundHaptics.selection()
            }
            .milehoundProminentButton()
            .tint(MilehoundBrandColors.brandBottom)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.32))
                    .frame(width: index == page ? 18 : 8, height: 8)
                    .animation(MilehoundMotion.gentle, value: page)
            }
        }
        .opacity(detailsReveal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.string("onboarding.step_a11y"), page + 1, pageCount))
    }

    private var bottomBar: some View {
        HStack {
            if page > 0 {
                Button(L10n.string("onboarding.back")) {
                    withAnimation(MilehoundMotion.gentle) {
                        page -= 1
                    }
                }
                .glassSecondaryInk()
            }

            Spacer()

            if page < pageCount - 1 {
                Button(L10n.string("onboarding.next")) {
                    withAnimation(MilehoundMotion.gentle) {
                        page += 1
                    }
                    MilehoundHaptics.selection()
                }
                .milehoundProminentButton()
                .tint(MilehoundBrandColors.brandBottom)
            } else {
                Button(L10n.string("onboarding.finish")) {
                    finishOnboarding()
                }
                .milehoundProminentButton()
                .tint(MilehoundBrandColors.brandBottom)
            }
        }
    }

    // MARK: - Entrance

    /// The cold-launch hound already played the brand entrance.
    private var welcomeAlreadyIntroduced: Bool {
        currentStep == .welcome
            && (LaunchIntroSession.shared.playedIntro || LaunchIntroSession.shared.coversFirstScreen)
    }

    @MainActor
    private func prepareEntrance() {
        if reduceMotion || welcomeAlreadyIntroduced {
            settleEntrance()
            return
        }
        brandReveal = 0
        heroReveal = 0
        driveInProgress = 0
        beatProgress = 0
        detailsReveal = 0
    }

    @MainActor
    private func settleEntrance() {
        brandReveal = 0
        heroReveal = 1
        driveInProgress = 1
        beatProgress = 1
        detailsReveal = 1
    }

    @MainActor
    private func runEntrance(for step: OnboardingStep) async {
        if reduceMotion || welcomeAlreadyIntroduced {
            settleEntrance()
            return
        }

        brandReveal = 0
        heroReveal = 0
        driveInProgress = step == .welcome ? 0 : 1
        beatProgress = 0
        detailsReveal = 0

        if step == .welcome {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                brandReveal = 1
            }
            let brandHold: Duration = layout.centersOnboardingColumn ? .milliseconds(900) : .milliseconds(420)
            try? await Task.sleep(for: brandHold)
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                heroReveal = 1
                brandReveal = 0
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                driveInProgress = 1
            }
            beatProgress = 1
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                heroReveal = 1
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                beatProgress = 1
            }
        }

        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            settleEntrance()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            detailsReveal = 1
        }
    }

    // MARK: - Actions

    private func openAppSettings() {
        SystemSettingsLink.openLocationPermission()
    }

    private func finishOnboarding() {
        settings.completeOnboarding()
        settings.skipCarSetup()
        MilehoundHaptics.pairingSucceeded()
    }
}

/// Landscape copy. Shrinks only when the block is taller than the page, so the title and last line stay on screen.
private struct WideOnboardingTextFit<Content: View>: View {
    var content: Content
    @State private var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            content
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { inner in
                        Color.clear.preference(key: WideOnboardingTextHeightKey.self, value: inner.size.height)
                    }
                }
                .scaleEffect(scale, anchor: .center)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .onPreferenceChange(WideOnboardingTextHeightKey.self) { height in
                    guard height > 1, geo.size.height > 1 else { return }
                    let next = min(1, (geo.size.height - 4) / height)
                    guard abs(next - scale) > 0.02 else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scale = next
                    }
                }
        }
        .clipped()
    }
}

private struct WideOnboardingTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    OnboardingView()
        .environment(LocationService())
}
