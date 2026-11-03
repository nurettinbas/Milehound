import Foundation

enum WeekSummaryRefresh {
    static let motionDuration: Duration = .milliseconds(800)

    static func animationID(text: String, token: Int) -> String {
        "\(token)#\(text)"
    }

    static func shouldPlayMotion(
        listMode: TripsTabListMode,
        weekSummaryText: String,
        reduceMotion: Bool
    ) -> Bool {
        listMode == .trips
            && !weekSummaryText.isEmpty
            && !reduceMotion
            && !UITestSupport.isEnabled
    }
}
