import Foundation
import SwiftUI

@MainActor
@Observable
final class TabSelection {
    static let shared = TabSelection()

    var selectedTab: AppTab = .trips
    /// Inbox is a root cover, not a page on the Trips stack.
    var showNotificationsCover = false
    /// Bumped when Start should reveal the recording card on Trips.
    private(set) var scrollToRecordingToken = 0
    /// Trips action sits with the bell in the trailing capsule. Hidden in merge mode and on the split library.
    var wideBookTrailingVisible = false
    /// Landscape book: bell, plus, and merge share one vertical capsule.
    var wideBookShowsPlusAndMerge = false
    var wideBookTrailingSymbol = "arrow.triangle.merge"
    var wideBookTrailingLabel = ""
    private(set) var wideBookTrailingToken = 0
    private(set) var wideBookJournalToken = 0
    private(set) var wideBookMergeToken = 0
    /// Set by care notification deep link; consumed by PairingTabView.
    private(set) var pendingVehicleCareID: UUID?
    private(set) var pendingStatsAnchor: StatsPremiumAnchor?
    private(set) var pendingTripID: UUID?
    /// Trips tab stack. Trip rows, travel rows, and notification deep links all write here.
    var tripsPath = NavigationPath()

    func openPairing() {
        selectedTab = .pairing
    }

    func openTrips() {
        selectedTab = .trips
    }

    func openNotifications() {
        showNotificationsCover = true
    }

    func closeNotifications() {
        showNotificationsCover = false
    }

    /// Switch to Trips and ask the list to show the recording card.
    func focusRecordingCard() {
        openTrips()
        scrollToRecordingToken += 1
    }

    func triggerWideBookTrailing() {
        wideBookTrailingToken += 1
    }

    func triggerNewJournal() {
        wideBookJournalToken += 1
    }

    func triggerMerge() {
        wideBookMergeToken += 1
    }

    func openVehicleCare(vehicleID: UUID) {
        pendingVehicleCareID = vehicleID
        selectedTab = .pairing
    }

    func consumePendingVehicleCareID() -> UUID? {
        let id = pendingVehicleCareID
        pendingVehicleCareID = nil
        return id
    }

    func openStats(anchor: StatsPremiumAnchor? = nil) {
        pendingStatsAnchor = anchor
        switch anchor {
        case .forecast, .recap, .routes, .achievements:
            selectedTab = .year
        default:
            selectedTab = .stats
        }
    }

    func openTrip(id: UUID) {
        pendingTripID = id
        selectedTab = .trips
        DevLog.shared.log(.tripDetail, "openTrip pending=\(id.uuidString.prefix(8)) path=\(tripsPath.count)")
    }

    /// Notification deep link: one trip on top of the list, never a second copy.
    func showFinishedTrip(_ trip: Trip) {
        var path = NavigationPath()
        path.append(trip)
        tripsPath = path
        selectedTab = .trips
        DevLog.shared.log(.tripDetail, "showFinishedTrip \(trip.id.uuidString.prefix(8)) path=\(tripsPath.count)")
    }

    /// Travel detail opens a member trip above the travel, on the same stack.
    func appendTrip(_ trip: Trip) {
        var path = tripsPath
        path.append(trip)
        tripsPath = path
        DevLog.shared.log(.tripDetail, "appendTrip \(trip.id.uuidString.prefix(8)) path=\(tripsPath.count)")
    }

    func consumePendingStatsAnchor() -> StatsPremiumAnchor? {
        let value = pendingStatsAnchor
        pendingStatsAnchor = nil
        return value
    }

    func consumePendingTripID() -> UUID? {
        let id = pendingTripID
        pendingTripID = nil
        return id
    }
}

enum StatsPremiumAnchor: String, Hashable {
    case goal
    case forecast
    case recap
    case routes
    case achievements
}

enum AppTab: Hashable {
    case trips
    case stats
    case pairing
    case year
    case settings

    /// Matches `ContentView` TabView order: Trips, Vehicles, Statistics, Recap, Settings.
    var tabBarIndex: Int {
        switch self {
        case .trips: 0
        case .pairing: 1
        case .stats: 2
        case .year: 3
        case .settings: 4
        }
    }
}
