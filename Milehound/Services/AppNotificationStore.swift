import Foundation
import Observation

enum AppNotificationKind: String {
    case tripStarted
    case tripEnded
    case tripDiscarded
    case tripsMerged
    case orphanStale
    case recordingStopped
    case pairingSuggestion
    case vehicleCareReminder
    case achievementUnlocked
    case yearRecapReady

    var systemImage: String {
        switch self {
        case .tripStarted: "play.circle.fill"
        case .tripEnded: "flag.checkered"
        case .tripDiscarded: "trash.circle.fill"
        case .tripsMerged: "arrow.triangle.merge"
        case .orphanStale: "exclamationmark.triangle.fill"
        case .recordingStopped: "stop.circle.fill"
        case .pairingSuggestion: "link.circle.fill"
        case .vehicleCareReminder: "wrench.and.screwdriver.fill"
        case .achievementUnlocked: "medal.fill"
        case .yearRecapReady: "sparkles"
        }
    }

    var tintName: String {
        switch self {
        case .tripStarted: "green"
        case .tripEnded: "blue"
        case .tripDiscarded: "gray"
        case .tripsMerged: "blue"
        case .orphanStale: "orange"
        case .recordingStopped: "red"
        case .pairingSuggestion: "blue"
        case .vehicleCareReminder: "orange"
        case .achievementUnlocked: "gold"
        case .yearRecapReady: "purple"
        }
    }
}

enum NotificationRoute: Equatable {
    case pairing
    case vehicleCare(UUID)
    case trip(UUID)
    case achievements
    case recap
    case none

    static func resolve(
        action: String?,
        target: String?,
        tripID: UUID?
    ) -> NotificationRoute {
        switch action {
        case TripNotificationService.openPairingAction:
            return .pairing
        case VehicleCareNotificationScheduler.openVehicleCareAction:
            if let target, let id = UUID(uuidString: target) {
                return .vehicleCare(id)
            }
            return .pairing
        case TripNotificationService.openTripAction:
            if let tripID {
                return .trip(tripID)
            }
            if let target, let id = UUID(uuidString: target) {
                return .trip(id)
            }
            return .none
        case TripNotificationService.openAchievementsAction:
            return .achievements
        case TripNotificationService.openRecapAction:
            return .recap
        default:
            if let tripID {
                return .trip(tripID)
            }
            return .none
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .pairing:
            TabSelection.shared.openPairing()
        case .vehicleCare(let id):
            TabSelection.shared.openVehicleCare(vehicleID: id)
        case .trip(let id):
            TabSelection.shared.openTrip(id: id)
        case .achievements:
            TabSelection.shared.openStats(anchor: .achievements)
        case .recap:
            TabSelection.shared.openStats(anchor: .recap)
        case .none:
            break
        }
    }

    var opensDestination: Bool {
        self != .none
    }
}

@MainActor
@Observable
final class AppNotificationStore {
    static let shared = AppNotificationStore()

    private(set) var items: [StoredAppNotification] = []

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private init() {
        reload()
    }

    func reload() {
        items = AppNotificationArchive.load()
    }

    func record(
        kind: AppNotificationKind,
        title: String,
        body: String,
        tripID: UUID? = nil,
        action: String? = nil,
        target: String? = nil,
        createdAt: Date = Date()
    ) {
        let record = StoredAppNotification(
            kind: kind.rawValue,
            title: title,
            body: body,
            createdAt: createdAt,
            tripID: tripID,
            action: action,
            target: target
        )
        items.insert(record, at: 0)
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        persist()
    }

    func recordSystemNotification(
        title: String,
        body: String,
        identifier: String,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        let kind = kindForIdentifier(identifier)
        let payload = routePayload(identifier: identifier, userInfo: userInfo)
        guard !containsDuplicate(title: title, body: body, within: 5) else { return }
        record(
            kind: kind,
            title: title,
            body: body,
            tripID: payload.tripID,
            action: payload.action,
            target: payload.target
        )
    }

    /// Refreshes an existing trip-started inbox row once the start place is known.
    /// - Returns: `true` when the stored body changed.
    @discardableResult
    func updateTripStartedBody(tripID: UUID, body: String) -> Bool {
        guard let index = items.firstIndex(where: {
            $0.tripID == tripID && kind(for: $0) == .tripStarted
        }) else { return false }

        let existing = items[index]
        guard existing.body != body else { return false }

        items[index] = StoredAppNotification(
            id: existing.id,
            kind: existing.kind,
            title: existing.title,
            body: body,
            createdAt: existing.createdAt,
            tripID: existing.tripID,
            action: existing.action,
            target: existing.target,
            isRead: existing.isRead
        )
        persist()
        return true
    }

    nonisolated static func enqueueSystemNotification(
        title: String,
        body: String,
        identifier: String,
        userInfo: [AnyHashable: Any] = [:],
        reload: Bool = false
    ) {
        let action = userInfo[TripNotificationService.actionUserInfoKey] as? String
        let tripRaw = userInfo[TripNotificationService.tripIDUserInfoKey] as? String
        let target = (userInfo[TripNotificationService.targetUserInfoKey] as? String)
            ?? (userInfo[VehicleCareNotificationScheduler.vehicleIDUserInfoKey] as? String)
        Task { @MainActor in
            var copied: [AnyHashable: Any] = [:]
            if let action {
                copied[TripNotificationService.actionUserInfoKey] = action
            }
            if let tripRaw {
                copied[TripNotificationService.tripIDUserInfoKey] = tripRaw
            }
            if let target {
                copied[TripNotificationService.targetUserInfoKey] = target
            }
            shared.recordSystemNotification(
                title: title,
                body: body,
                identifier: identifier,
                userInfo: copied
            )
            if reload {
                shared.reload()
            }
        }
    }

    func markRead(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
        persist()
    }

    func markAllRead() {
        guard items.contains(where: { !$0.isRead }) else { return }
        for index in items.indices {
            items[index].isRead = true
        }
        persist()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        guard !items.isEmpty else { return }
        items.removeAll()
        persist()
    }

    func kind(for record: StoredAppNotification) -> AppNotificationKind {
        AppNotificationKind(rawValue: record.kind) ?? .tripEnded
    }

    func route(for record: StoredAppNotification) -> NotificationRoute {
        NotificationRoute.resolve(
            action: record.action ?? inferredAction(identifierHint: record.kind, tripID: record.tripID),
            target: record.target,
            tripID: record.tripID
        )
    }

    private func persist() {
        AppNotificationArchive.save(items)
    }

    private func containsDuplicate(title: String, body: String, within seconds: TimeInterval) -> Bool {
        guard let latest = items.first else { return false }
        let isRecent = Date().timeIntervalSince(latest.createdAt) <= seconds
        return isRecent && latest.title == title && latest.body == body
    }

    private func kindForIdentifier(_ identifier: String) -> AppNotificationKind {
        if identifier.contains(".recap.") { return .yearRecapReady }
        if identifier.contains(".achievement.") { return .achievementUnlocked }
        if identifier.contains("started") { return .tripStarted }
        if identifier.contains("ended") { return .tripEnded }
        if identifier.contains("discarded") { return .tripDiscarded }
        if identifier.contains("merged") { return .tripsMerged }
        if identifier.contains("orphan") { return .orphanStale }
        if identifier.contains("stopped") { return .recordingStopped }
        if identifier.contains("pairing") { return .pairingSuggestion }
        if identifier.contains(".care.") { return .vehicleCareReminder }
        return .tripEnded
    }

    private func tripIDFromIdentifier(_ identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard let raw = parts.last else { return nil }
        return UUID(uuidString: String(raw))
    }

    private func routePayload(
        identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> (action: String?, target: String?, tripID: UUID?) {
        let action = (userInfo[TripNotificationService.actionUserInfoKey] as? String)
            ?? inferredAction(identifier: identifier)
        let tripFromInfo = (userInfo[TripNotificationService.tripIDUserInfoKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let targetFromInfo = (userInfo[TripNotificationService.targetUserInfoKey] as? String)
            ?? (userInfo[VehicleCareNotificationScheduler.vehicleIDUserInfoKey] as? String)
        return (
            action,
            targetFromInfo ?? targetFromIdentifier(identifier),
            tripFromInfo ?? tripIDFromIdentifier(identifier)
        )
    }

    private func inferredAction(identifier: String) -> String? {
        if identifier.contains(".care.") {
            return VehicleCareNotificationScheduler.openVehicleCareAction
        }
        if identifier.contains(".recap.") {
            return TripNotificationService.openRecapAction
        }
        if identifier.contains(".achievement.") {
            return TripNotificationService.openAchievementsAction
        }
        if identifier.contains("pairing") {
            return TripNotificationService.openPairingAction
        }
        if identifier.contains(".trip.") || identifier.contains("orphan") {
            return TripNotificationService.openTripAction
        }
        return nil
    }

    private func inferredAction(identifierHint kind: String, tripID: UUID?) -> String? {
        switch AppNotificationKind(rawValue: kind) {
        case .vehicleCareReminder: VehicleCareNotificationScheduler.openVehicleCareAction
        case .yearRecapReady: TripNotificationService.openRecapAction
        case .achievementUnlocked: TripNotificationService.openAchievementsAction
        case .pairingSuggestion: TripNotificationService.openPairingAction
        case .tripStarted, .tripEnded, .tripsMerged, .orphanStale:
            tripID == nil ? nil : TripNotificationService.openTripAction
        default:
            nil
        }
    }

    private func targetFromIdentifier(_ identifier: String) -> String? {
        if identifier.contains(".care.") {
            let parts = identifier.split(separator: ".")
            if parts.count >= 5 {
                return String(parts[2])
            }
        }
        if identifier.contains(".recap.") {
            return identifier.split(separator: ".").last.map(String.init)
        }
        if let range = identifier.range(of: "milehound.achievement.") {
            let rest = String(identifier[range.upperBound...])
            if rest != "batch" { return rest }
        }
        return nil
    }
}
