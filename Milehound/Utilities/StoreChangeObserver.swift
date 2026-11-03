import Combine
import SwiftData
import SwiftUI

extension View {
    /// Runs `action` whenever any `ModelContext` saves, for views that keep their own fetched
    /// arrays instead of a `@Query` and so have to reload themselves.
    ///
    /// `ModelContext.didSave` is delivered on whichever thread performed the save. Background
    /// workers such as `TripDerivedBackfiller` and `TripRollupRebuilder` save from their own
    /// `@ModelActor`. SwiftUI's `onReceive` requires the publisher itself to emit on the main
    /// thread — hopping only the handler still trips "Publishing changes from background threads".
    ///
    /// `receive(on:)` uses a scheduler that runs immediately when already on main. A plain
    /// `DispatchQueue.main` hop would defer a deletion by a runloop turn, and rendering a row
    /// that still points at a deleted model is a crash, not a glitch.
    func onStoreSave(perform action: @escaping @Sendable @MainActor () -> Void) -> some View {
        onReceive(
            NotificationCenter.default
                .publisher(for: ModelContext.didSave)
                .receive(on: MainImmediateScheduler.shared)
        ) { _ in
            MainActor.assumeIsolated(action)
        }
    }
}

/// `DispatchQueue.main` always async-hops, even when the caller is already on main.
/// This scheduler keeps that case synchronous so `onStoreSave` can reload before the next body.
private struct MainImmediateScheduler: Scheduler {
    typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
    typealias SchedulerOptions = Never

    static let shared = MainImmediateScheduler()

    var now: SchedulerTimeType { DispatchQueue.main.now }
    var minimumTolerance: SchedulerTimeType.Stride { DispatchQueue.main.minimumTolerance }

    func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            nonisolated(unsafe) let action = action
            DispatchQueue.main.async {
                action()
            }
        }
    }

    func schedule(
        after date: SchedulerTimeType,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) {
        nonisolated(unsafe) let action = action
        DispatchQueue.main.schedule(after: date, tolerance: tolerance, options: nil) {
            action()
        }
    }

    func schedule(
        after date: SchedulerTimeType,
        interval: SchedulerTimeType.Stride,
        tolerance: SchedulerTimeType.Stride,
        options: SchedulerOptions?,
        _ action: @escaping () -> Void
    ) -> any Cancellable {
        nonisolated(unsafe) let action = action
        return DispatchQueue.main.schedule(
            after: date,
            interval: interval,
            tolerance: tolerance,
            options: nil
        ) {
            action()
        }
    }
}
