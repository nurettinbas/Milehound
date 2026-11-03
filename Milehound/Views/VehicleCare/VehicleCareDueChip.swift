import SwiftUI

/// Warning (orange) vs alert (red) for urgent care due states.
enum VehicleCareUrgencyBand: String, Equatable, Sendable {
    case warning
    case alert

    var accent: Color {
        switch self {
        case .warning: .orange
        case .alert: .red
        }
    }
}

enum VehicleCareUrgencyStyle {
    static func band(for state: VehicleCareDueState) -> VehicleCareUrgencyBand? {
        guard state.isUrgent else { return nil }
        return state.isOverdue ? .alert : .warning
    }

    static func accent(for state: VehicleCareDueState) -> Color? {
        band(for: state)?.accent
    }

    /// Short days-left / overdue label when urgent; otherwise `nil`.
    static func chipText(for state: VehicleCareDueState) -> String? {
        guard band(for: state) != nil else { return nil }
        return VehicleCareDueCalculator.shortSubtitle(for: state)
    }
}

/// Which surface owns a one-shot entrance (chip vs reminder icon stay independent).
enum VehicleCareUrgencyEntranceRole: String, Sendable {
    case chip
    case icon
}

/// Process-lifetime one-shot keys (not UserDefaults — relaunch can show entrances again).
@MainActor
enum VehicleCareUrgencyEntranceStore {
    private static var played: Set<String> = []

    static func consume(
        role: VehicleCareUrgencyEntranceRole,
        scheduleID: UUID,
        band: VehicleCareUrgencyBand
    ) -> Bool {
        let key = role.rawValue + "." + scheduleID.uuidString + "." + band.rawValue
        if played.contains(key) { return false }
        played.insert(key)
        return true
    }

#if DEBUG
    static func resetAll() {
        played.removeAll()
    }
#endif
}

/// Capsule label: filled orange/red plate + white caption (days left / due today / overdue).
/// Vehicles list can pass `leadingSystemImage` + `title` so the chip reads e.g. wrench · Service · 2 days left.
struct VehicleCareDueChip: View {
    let text: String
    let band: VehicleCareUrgencyBand
    var leadingSystemImage: String? = nil
    var title: String? = nil
    /// Parent sets `true` once after a successful store consume.
    var playEntrance: Bool = false

    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var shakeX: CGFloat = 0
    @State private var didAnimate = false

    private var accessibilityText: String {
        [title, text].compactMap { $0 }.joined(separator: " — ")
    }

    var body: some View {
        HStack(spacing: 4) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("·")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(band.accent, in: Capsule())
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(x: shakeX)
        .accessibilityIdentifier("vehicle.care.due.chip")
        .accessibilityLabel(accessibilityText)
        .onChange(of: playEntrance) { _, shouldPlay in
            guard shouldPlay else { return }
            runEntranceIfNeeded()
        }
        .onAppear {
            if playEntrance { runEntranceIfNeeded() }
        }
    }

    private func runEntranceIfNeeded() {
        guard !didAnimate else { return }
        didAnimate = true
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            switch band {
            case .warning:
                scale = 0.86
                opacity = 0.55
            case .alert:
                scale = 0.78
                opacity = 0.4
                shakeX = 0
            }
        }
        switch band {
        case .warning: playWarningEntrance()
        case .alert: playAlertEntrance()
        }
    }

    private func playWarningEntrance() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            scale = 1.06
            opacity = 1
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86).delay(0.18)) {
            scale = 1
        }
        withAnimation(.easeInOut(duration: 0.22).delay(0.28)) {
            opacity = 0.78
        }
        withAnimation(.easeInOut(duration: 0.22).delay(0.5)) {
            opacity = 1
        }
    }

    private func playAlertEntrance() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            scale = 1.14
            opacity = 1
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.82).delay(0.16)) {
            scale = 1
        }
        withAnimation(.easeInOut(duration: 0.06).delay(0.08)) { shakeX = 5 }
        withAnimation(.easeInOut(duration: 0.06).delay(0.14)) { shakeX = -5 }
        withAnimation(.easeInOut(duration: 0.06).delay(0.2)) { shakeX = 4 }
        withAnimation(.easeInOut(duration: 0.06).delay(0.26)) { shakeX = -3 }
        withAnimation(.easeInOut(duration: 0.08).delay(0.32)) { shakeX = 0 }
    }
}

/// Leading reminder kind tile — owns its own warning/alert entrance on appear.
struct VehicleCareUrgencyIconTile: View {
    let systemImage: String
    let scheduleID: UUID
    let band: VehicleCareUrgencyBand?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var shakeX: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var glow: Double = 0
    @State private var symbolBounceToken = 0
    @State private var didPlay = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce, options: .nonRepeating, value: symbolBounceToken)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(band?.accent ?? shellPalette.tintColor(for: colorScheme))
            )
            .scaleEffect(scale)
            .offset(x: shakeX)
            .rotationEffect(.degrees(rotation))
            .shadow(color: (band?.accent ?? .clear).opacity(glow), radius: glow > 0 ? 10 : 0)
            .task(id: entranceTaskID) {
                await playEntranceIfNeeded()
            }
    }

    private var entranceTaskID: String {
        "\(scheduleID.uuidString)-\(band?.rawValue ?? "none")"
    }

    @MainActor
    private func playEntranceIfNeeded() async {
        guard let band, !reduceMotion, !didPlay else { return }
        didPlay = true

        // Let the row land on screen before animating.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            scale = band == .alert ? 0.55 : 0.7
            shakeX = 0
            rotation = 0
            glow = 0
        }

        symbolBounceToken += 1

        switch band {
        case .warning:
            withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
                scale = 1.22
                glow = 0.65
            }
            withAnimation(.easeInOut(duration: 0.12).delay(0.1)) { rotation = -10 }
            withAnimation(.easeInOut(duration: 0.12).delay(0.22)) { rotation = 9 }
            withAnimation(.easeInOut(duration: 0.12).delay(0.34)) { rotation = -5 }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78).delay(0.46)) {
                rotation = 0
                scale = 1
                glow = 0
            }
        case .alert:
            withAnimation(.spring(response: 0.24, dampingFraction: 0.42)) {
                scale = 1.34
                glow = 0.85
            }
            withAnimation(.easeInOut(duration: 0.05).delay(0.05)) { shakeX = 8 }
            withAnimation(.easeInOut(duration: 0.05).delay(0.1)) { shakeX = -8 }
            withAnimation(.easeInOut(duration: 0.05).delay(0.15)) { shakeX = 7 }
            withAnimation(.easeInOut(duration: 0.05).delay(0.2)) { shakeX = -6 }
            withAnimation(.easeInOut(duration: 0.05).delay(0.25)) { shakeX = 4 }
            withAnimation(.easeInOut(duration: 0.06).delay(0.3)) { shakeX = 0 }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7).delay(0.34)) {
                scale = 1
                glow = 0
            }
        }
    }
}
