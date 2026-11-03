import Foundation
import os

/// Instruments the paths that historically blocked the main thread.
/// Profile with Instruments → os_signpost, subsystem `com.milehound.app`, category `Performance`.
/// `TripsTabAppear` wraps the trip list's `onAppear`. After the first load it must stay
/// under a frame and must not fetch trips or read the notification archive.
enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.milehound.app",
        category: "Performance"
    )

    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }
}
