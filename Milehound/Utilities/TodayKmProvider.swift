import Foundation

enum TodayKmProvider {
    private static let suiteName = "group.com.milehound.app"

    static func syncTodayDistance(_ meters: Double) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(meters, forKey: "stats.todayDistance")
    }

    static func todayKilometers() -> Double {
        let defaults = UserDefaults(suiteName: suiteName)
        let meters = defaults?.double(forKey: "stats.todayDistance") ?? 0
        return meters / 1000
    }
}
