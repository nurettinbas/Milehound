import SwiftUI
import UserNotifications

struct PermissionStatusCapsule: View {
  let icon: String
  let label: String
  let fillColors: [Color]
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption2)
      Text(label)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .fixedSize(horizontal: true, vertical: false)
    .background {
      Capsule(style: .continuous)
        .fill(
          LinearGradient(
            colors: fillColors,
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(
              Color.white.opacity(colorScheme == .dark ? 0.28 : 0.42),
              lineWidth: 0.75
            )
        }
    }
    .shadow(
      color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.18),
      radius: 2,
      y: 1
    )
    .compositingGroup()
    .accessibilityLabel(label)
  }
}

struct LocationPermissionBadge: View {
  let state: LocationService.AuthorizationState
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    PermissionStatusCapsule(icon: icon, label: label, fillColors: fillColors)
  }

  private var icon: String {
    switch state {
    case .authorizedAlways: "location.fill"
    case .authorizedWhenInUse: "location.circle"
    case .denied, .restricted: "location.slash.fill"
    case .notDetermined: "location"
    }
  }

  private var label: String {
    switch state {
    case .authorizedAlways: L10n.locationBadgeAlways
    case .authorizedWhenInUse: L10n.locationBadgeWhenInUse
    case .denied, .restricted, .notDetermined: L10n.locationBadgeDenied
    }
  }

  private var color: Color {
    switch state {
    case .authorizedAlways: Color(red: 0.12, green: 0.62, blue: 0.30)
    case .authorizedWhenInUse: GlassSemantic.paused(for: colorScheme)
    case .denied, .restricted, .notDetermined: GlassSemantic.destructive(for: colorScheme)
    }
  }

  private var fillColors: [Color] {
    guard state == .authorizedAlways else {
      return [color, color]
    }
    return [
      Color(red: 0.18, green: 0.70, blue: 0.36),
      Color(red: 0.09, green: 0.55, blue: 0.25)
    ]
  }
}

struct NotificationPermissionBadge: View {
  let status: UNAuthorizationStatus
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    PermissionStatusCapsule(icon: icon, label: label, fillColors: fillColors)
  }

  private var icon: String {
    switch status {
    case .authorized, .provisional, .ephemeral: "bell.fill"
    case .denied: "bell.slash.fill"
    case .notDetermined: "bell"
    @unknown default: "bell.slash.fill"
    }
  }

  private var label: String {
    switch status {
    case .authorized, .provisional, .ephemeral: L10n.notificationsBadgeAllowed
    case .notDetermined: L10n.notificationsBadgeAsk
    case .denied: L10n.notificationsBadgeDenied
    @unknown default: L10n.notificationsBadgeDenied
    }
  }

  private var fillColors: [Color] {
    switch status {
    case .authorized, .provisional, .ephemeral:
      [
        Color(red: 0.18, green: 0.70, blue: 0.36),
        Color(red: 0.09, green: 0.55, blue: 0.25)
      ]
    case .notDetermined:
      [GlassSemantic.paused(for: colorScheme), GlassSemantic.paused(for: colorScheme)]
    case .denied:
      [GlassSemantic.destructive(for: colorScheme), GlassSemantic.destructive(for: colorScheme)]
    @unknown default:
      [GlassSemantic.destructive(for: colorScheme), GlassSemantic.destructive(for: colorScheme)]
    }
  }
}

struct LocationAlwaysRequiredBanner: View {
  @Environment(LocationService.self) private var locationService
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    if locationService.authorizationState == .authorizedAlways {
      EmptyView()
    } else {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.pairingLocationWarning)
            .font(.caption)
            .foregroundStyle(GlassText.primary(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
          locationAction
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.12))
      .glassCard(cornerRadius: 12, contentInset: 0)
    }
  }

  @ViewBuilder
  private var locationAction: some View {
    switch locationService.authorizationState {
    case .notDetermined, .authorizedWhenInUse:
      Button(L10n.locationBannerGrant) {
        locationService.requestPermission()
      }
      .font(.caption.bold())
    case .denied, .restricted:
      Button(L10n.locationBannerSettings) {
        SystemSettingsLink.openLocationPermission()
      }
      .font(.caption.bold())
    case .authorizedAlways:
      EmptyView()
    }
  }
}

struct LocationPermissionBanner: View {
  @Environment(LocationService.self) private var locationService
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    switch locationService.authorizationState {
    case .authorizedAlways:
      EmptyView()
    case .authorizedWhenInUse:
      banner(
        message: L10n.string("location.banner.when_in_use"),
        systemImage: "location.circle",
        openSettings: true
      )
    case .denied, .restricted:
      banner(
        message: L10n.string("location.banner.denied"),
        systemImage: "location.slash.fill",
        openSettings: true
      )
    case .notDetermined:
      banner(
        message: L10n.string("location.banner.not_determined"),
        systemImage: "location.fill",
        openSettings: false,
        actionTitle: L10n.string("location.banner.grant"),
        action: { locationService.requestPermission() }
      )
    }
  }

  @ViewBuilder
  private func banner(
    message: String,
    systemImage: String,
    openSettings: Bool,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(.orange)
        Text(message)
          .font(.caption)
          .foregroundStyle(GlassText.primary(for: colorScheme))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      bannerAction(openSettings: openSettings, actionTitle: actionTitle, action: action)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.12))
    .glassCard(cornerRadius: 12, contentInset: 0)
    .padding(.horizontal)
  }

  private func bannerButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .font(.caption.bold())
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .trailing)
  }

  @ViewBuilder
  private func bannerAction(
    openSettings: Bool,
    actionTitle: String?,
    action: (() -> Void)?
  ) -> some View {
    if let actionTitle, let action {
      bannerButton(actionTitle, action: action)
    } else if openSettings {
      bannerButton(L10n.string("location.banner.settings")) {
        SystemSettingsLink.openLocationPermission()
      }
    }
  }
}

struct GPSQualityBadge: View {
  let quality: LocationService.GPSQuality
  var compact: Bool = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: compact ? 3 : 4) {
      Image(systemName: icon)
        .font(compact ? .system(size: 9, weight: .semibold) : .caption.weight(.semibold))
        .symbolEffect(.bounce, value: quality)
      Text(label)
        .font(compact ? .system(size: 10, weight: .medium) : .caption.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(compact ? 0.75 : 1)
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, compact ? 6 : 8)
    .padding(.vertical, compact ? 3 : 6)
    .background(color)
    .clipShape(Capsule())
    .compositingGroup()
    .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: quality)
    .accessibilityLabel(label)
  }

  private var icon: String {
    switch quality {
    case .good: "location.fill"
    case .weak: "location.circle"
    case .lost: "location.slash"
    }
  }

  private var label: String {
    switch quality {
    case .good: L10n.string("gps.quality.good")
    case .weak: L10n.string("gps.quality.weak")
    case .lost: L10n.string("gps.quality.lost")
    }
  }

  private var color: Color {
    switch quality {
    case .good: .green
    case .weak: .orange
    case .lost: .red
    }
  }
}
