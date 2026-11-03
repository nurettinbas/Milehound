import SwiftData
import UIKit
import XCTest
@testable import Milehound

@MainActor
final class TripMapSnapshotCacheTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        let cache = TripMapSnapshotCache.shared
        if let container {
            let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
            for trip in trips {
                cache.remove(for: trip.id)
            }
        }
        cache.clearMemory()
        cache.resetRenderInvocationCount()
        cache.resetTestRenderer()
        container = nil
        super.tearDown()
    }

    func testMemoryHitDoesNotRender() async throws {
        let trip = try insertTrip(pointCount: 12)
        let cache = TripMapSnapshotCache.shared
        cache.storeForTesting(Self.makeSwatch(), tripID: trip.id, appearance: .light)
        cache.resetRenderInvocationCount()
        cache.testRenderer = {
            XCTFail("Renderer must not run on a memory hit")
            return nil
        }

        let image = await cache.snapshot(
            for: trip,
            appearance: .light,
            container: container
        )

        XCTAssertNotNil(image)
        XCTAssertEqual(cache.renderInvocationCount, 0)
    }

    func testDiskHitDoesNotRender() async throws {
        let trip = try insertTrip(pointCount: 14)
        let cache = TripMapSnapshotCache.shared
        cache.storeForTesting(Self.makeSwatch(), tripID: trip.id, appearance: .dark)
        try await Task.sleep(for: .milliseconds(50))
        cache.clearMemory()
        cache.resetRenderInvocationCount()
        cache.testRenderer = {
            XCTFail("Renderer must not run on a disk hit")
            return nil
        }

        let image = await cache.snapshot(
            for: trip,
            appearance: .dark,
            container: container
        )

        XCTAssertNotNil(image)
        XCTAssertEqual(cache.renderInvocationCount, 0)
        XCTAssertNotNil(cache.cachedImage(for: trip.id, appearance: .dark))
    }

    func testRenderGateRunsOneAtATime() async throws {
        let first = try insertTrip(pointCount: 16)
        let second = try insertTrip(pointCount: 18)
        let cache = TripMapSnapshotCache.shared
        let probe = RenderProbe()
        cache.testRenderer = {
            probe.enter()
            try? await Task.sleep(for: .milliseconds(40))
            probe.leave()
            return Self.makeSwatch()
        }

        async let firstImage = cache.snapshot(
            for: first,
            appearance: .light,
            container: container
        )
        async let secondImage = cache.snapshot(
            for: second,
            appearance: .light,
            container: container
        )
        let images = await (firstImage, secondImage)

        XCTAssertNotNil(images.0)
        XCTAssertNotNil(images.1)
        XCTAssertEqual(cache.renderInvocationCount, 2)
        XCTAssertEqual(probe.maxConcurrent, 1)
    }

    func testCancelledWaiterDoesNotRenderOrHoldTheGate() async throws {
        let first = try insertTrip(pointCount: 15)
        let second = try insertTrip(pointCount: 17)
        let third = try insertTrip(pointCount: 19)
        let cache = TripMapSnapshotCache.shared
        let latch = RenderLatch()
        cache.testRenderer = {
            latch.markStarted()
            await latch.wait()
            return Self.makeSwatch()
        }

        let firstTask = Task {
            await cache.snapshot(for: first, appearance: .light, container: self.container)
        }
        await latch.waitUntilStarted()

        let secondTask = Task {
            await cache.snapshot(for: second, appearance: .light, container: self.container)
        }
        try await Task.sleep(for: .milliseconds(30))
        secondTask.cancel()
        let cancelled = await secondTask.value
        XCTAssertNil(cancelled)

        latch.release()
        let firstImage = await firstTask.value
        XCTAssertNotNil(firstImage)
        XCTAssertEqual(cache.renderInvocationCount, 1)

        let thirdImage = await cache.snapshot(
            for: third,
            appearance: .light,
            container: container
        )
        XCTAssertNotNil(thirdImage)
        XCTAssertEqual(cache.renderInvocationCount, 2)
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        if container == nil {
            container = try ModelContainerFactory.makeInMemory()
        }
        let context = container.mainContext
        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(pointCount) * 5),
            distanceMeters: Double(pointCount) * 12
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.0 + Double(pointCount) * 0.0001
        trip.endLongitude = 29.0 + Double(pointCount) * 0.0001
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 5),
                latitude: 41.0 + Double(index) * 0.0001,
                longitude: 29.0 + Double(index) * 0.0001,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            context.insert(point)
        }
        try context.save()
        return trip
    }

    private static func makeSwatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

private final class RenderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var maxConcurrent = 0

    func enter() {
        lock.lock()
        current += 1
        maxConcurrent = max(maxConcurrent, current)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        current -= 1
        lock.unlock()
    }
}

private final class RenderLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hold: CheckedContinuation<Void, Never>?

    func markStarted() {
        lock.lock()
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started {
                lock.unlock()
                continuation.resume()
                return
            }
            startWaiters.append(continuation)
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            hold = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        released = true
        let continuation = hold
        hold = nil
        lock.unlock()
        continuation?.resume()
    }
}
