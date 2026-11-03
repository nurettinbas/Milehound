import SwiftUI
import XCTest
@testable import Milehound

final class LaunchIntroTimelineTests: XCTestCase {
    func testStandardBeatsAreOrderedAndShort() {
        let timeline = LaunchIntroTimeline.standard
        assertOrdered(timeline)
        XCTAssertEqual(timeline.total, 1.715, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(timeline.closeEnd - timeline.runEnd, 0.5, "the close needs room to read")
        XCTAssertLessThanOrEqual(timeline.total - timeline.closeEnd, 0.4, "the exit stays quick")
        XCTAssertTrue(timeline.allowsMotion)
        XCTAssertEqual(timeline.preferredFrameRate, 120)
    }

    func testReduceMotionIsAStillCrossfade() {
        let timeline = LaunchIntroTimeline.reduceMotion
        XCTAssertFalse(timeline.allowsMotion)
        XCTAssertEqual(timeline.total, MilehoundMotion.launchIntroReduceMotionDuration, accuracy: 0.001)
    }

    func testLowPowerIsShorterAt60Hz() {
        let timeline = LaunchIntroTimeline.lowPower
        assertOrdered(timeline)
        XCTAssertEqual(timeline.total, MilehoundMotion.launchIntroLowPowerDuration, accuracy: 0.001)
        XCTAssertLessThan(timeline.total, LaunchIntroTimeline.standard.total)
        XCTAssertTrue(timeline.allowsMotion)
        XCTAssertEqual(timeline.preferredFrameRate, 60)
    }

    func testSkipIsAQuarterSecond() {
        let timeline = LaunchIntroTimeline.skip
        XCTAssertEqual(timeline.total, MilehoundMotion.launchIntroSkipDuration, accuracy: 0.001)
        XCTAssertFalse(timeline.allowsMotion)
        XCTAssertEqual(LaunchIntroTimeline.resolve(reduceMotion: true, lowPower: true).total, LaunchIntroTimeline.reduceMotion.total)
        XCTAssertEqual(LaunchIntroTimeline.resolve(reduceMotion: false, lowPower: true).total, LaunchIntroTimeline.lowPower.total)
    }

    private func assertOrdered(_ timeline: LaunchIntroTimeline, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(timeline.enterEnd, 0, file: file, line: line)
        XCTAssertLessThan(timeline.enterEnd, timeline.runEnd, file: file, line: line)
        XCTAssertLessThan(timeline.runEnd, timeline.closeEnd, file: file, line: line)
        XCTAssertLessThan(timeline.closeEnd, timeline.total, file: file, line: line)
    }
}

final class LaunchIntroHoundRigTests: XCTestCase {
    private let rig = LaunchIntroHoundRig.standard

    func testGaitStartsAndEndsOnTheLogoPose() {
        for timeline in [LaunchIntroTimeline.standard, .lowPower] {
            for curve in curves {
                XCTAssertEqual(rig.offset(curve, at: 0, timeline: timeline), 0, accuracy: 1e-6)
                XCTAssertEqual(rig.offset(curve, at: timeline.closeEnd, timeline: timeline), 0, accuracy: 1e-6)
                XCTAssertEqual(rig.offset(curve, at: timeline.total, timeline: timeline), 0, accuracy: 1e-6)
            }
        }
    }

    func testEveryBoneMovesDuringTheRunWithoutSpinning() {
        let timeline = LaunchIntroTimeline.standard
        for bone in rig.bones {
            let swings = stride(from: timeline.enterEnd, through: timeline.runEnd, by: 0.01)
                .map { abs(rig.offset(bone.swing, at: $0, timeline: timeline)) }
            let peak = swings.max() ?? 0
            XCTAssertGreaterThan(peak, 0.04, bone.asset)
            XCTAssertLessThan(peak, 2, bone.asset)
        }
    }

    func testCurvesLoopOncePerStride() {
        for curve in curves {
            XCTAssertEqual(curve.value(at: 0), curve.value(at: 1), accuracy: 1e-9)
            XCTAssertEqual(curve.value(at: 0.3), curve.value(at: 2.3), accuracy: 1e-9)
        }
        XCTAssertEqual(LaunchIntroHoundRig.Curve.still.value(at: 0.4), 0)
        let held = LaunchIntroHoundRig.Curve(bias: 0.3, cosines: [0.1], sines: [0])
        XCTAssertEqual(held.value(at: 0), 0.4, accuracy: 1e-9)
        XCTAssertEqual(held.value(at: 0.5), 0.2, accuracy: 1e-9)
    }

    func testEnvelopeHoldsThroughTheRunThenDiesOut() {
        let timeline = LaunchIntroTimeline.standard
        XCTAssertEqual(LaunchIntroHoundRig.envelope(at: timeline.enterEnd, timeline: timeline), 1, accuracy: 1e-6)
        XCTAssertEqual(LaunchIntroHoundRig.envelope(at: timeline.runEnd, timeline: timeline), 1, accuracy: 1e-6)
        XCTAssertEqual(LaunchIntroHoundRig.envelope(at: timeline.closeEnd, timeline: timeline), 0, accuracy: 1e-6)
        var previous: CGFloat = 1
        for time in stride(from: timeline.runEnd, through: timeline.closeEnd, by: 0.02) {
            let value = LaunchIntroHoundRig.envelope(at: time, timeline: timeline)
            XCTAssertLessThanOrEqual(value, previous + 1e-9)
            previous = value
        }
    }

    func testReduceMotionNeverMoves() {
        for curve in curves {
            XCTAssertEqual(rig.offset(curve, at: 0.1, timeline: .reduceMotion), 0)
        }
    }

    func testBonesAreUniqueAndJointsSitOnTheCanvas() {
        XCTAssertEqual(rig.bones.count, 11)
        XCTAssertEqual(Set(rig.bones.map(\.asset)).count, rig.bones.count)
        let canvas = CGRect(origin: .zero, size: rig.canvas)
        for bone in rig.bones {
            XCTAssertTrue(canvas.contains(bone.joint), bone.asset)
        }
        XCTAssertEqual(rig.stride, MilehoundMotion.launchIntroGallopStride)
    }

    func testStrideSamplesLoopOnceAndMatchTheCurve() {
        for curve in curves {
            let samples = LaunchIntroHoundLayerTree.strideSamples(curve: curve, unit: 2)
            XCTAssertEqual(samples.times.count, 17)
            XCTAssertEqual(samples.values.count, 17)
            XCTAssertEqual(samples.values.first ?? 0, samples.values.last ?? 1, accuracy: 1e-9)
            for (index, value) in samples.values.enumerated() {
                let phase = CGFloat(index) / 16
                XCTAssertEqual(value, curve.value(at: phase) * 2, accuracy: 1e-9)
            }
        }
    }

    func testStrideLoopDurationIsTheGallopStride() {
        let animation = LaunchIntroHoundLayerTree.strideLoop(
            "transform.rotation.z",
            rig: rig,
            curve: rig.torso.swing
        )
        XCTAssertEqual(animation.duration, MilehoundMotion.launchIntroGallopStride, accuracy: 1e-9)
        XCTAssertEqual(animation.calculationMode, .cubic)
        XCTAssertEqual(animation.repeatCount, .greatestFiniteMagnitude)
    }

    func testEnvelopedGaitStartsAndEndsOnTheLogoPose() throws {
        let timeline = LaunchIntroTimeline.standard
        let animation = LaunchIntroHoundLayerTree.envelopedGait(
            "transform.rotation.z",
            rig: rig,
            curve: rig.torso.swing,
            timeline: timeline
        )
        let values = try XCTUnwrap(animation.values as? [NSNumber]).map(\.doubleValue)
        XCTAssertEqual(values.first ?? 1, 0, accuracy: 1e-6)
        XCTAssertEqual(values.last ?? 1, 0, accuracy: 1e-6)
        XCTAssertEqual(animation.duration, timeline.closeEnd, accuracy: 1e-9)
    }

    func testTintedPartUsesTheFillColor() throws {
        let parts = try XCTUnwrap(LaunchIntroHoundParts.load())
        let source = try XCTUnwrap(parts.cgImage(named: "MilehoundHoundFront", tint: nil))
        let tinted = try XCTUnwrap(parts.cgImage(named: "MilehoundHoundFront", tint: .systemBlue))
        XCTAssertEqual(tinted.width, source.width)
        XCTAssertEqual(tinted.height, source.height)
        let sourceData = try XCTUnwrap(source.dataProvider?.data) as Data
        let tintedData = try XCTUnwrap(tinted.dataProvider?.data) as Data
        XCTAssertNotEqual(sourceData, tintedData)
    }

    func testLayerTreeMountsEveryBone() throws {
        let parts = try XCTUnwrap(LaunchIntroHoundParts.load())
        let host = CALayer()
        let mounted = LaunchIntroHoundLayerTree.add(
            parts: parts,
            in: CGRect(x: 0, y: 0, width: 100, height: 56),
            on: host,
            contentsScale: 2
        )
        XCTAssertEqual(mounted.joints.count, rig.bones.count)
        XCTAssertEqual(mounted.imageLayers.count, rig.bones.count)
        XCTAssertEqual(host.sublayers?.count, 1)
        XCTAssertEqual(mounted.root.superlayer, host)
    }

    private var curves: [LaunchIntroHoundRig.Curve] {
        rig.bones.map(\.swing) + [rig.bob]
    }
}

final class LaunchIntroGateTests: XCTestCase {
    func testPlaysOnANormalColdLaunch() {
        let decision = LaunchIntroGate.decide(
            isUITesting: false,
            isActiveRecording: false,
            hasPendingRecordingRequest: false,
            openedFromURL: false,
            openedFromNotification: false,
            voiceOver: false,
            alreadyPlayed: false,
            isFirstScene: true
        )
        XCTAssertTrue(decision.plays)
        XCTAssertNil(decision.skipReason)
    }

    func testEachSkipReason() {
        XCTAssertEqual(decide(isUITesting: true).skipReason, .uiTest)
        XCTAssertEqual(decide(isActiveRecording: true).skipReason, .activeRecording)
        XCTAssertEqual(decide(hasPendingRecordingRequest: true).skipReason, .pendingRecordingRequest)
        XCTAssertEqual(decide(openedFromURL: true).skipReason, .openedFromURL)
        XCTAssertEqual(decide(openedFromNotification: true).skipReason, .notificationTap)
        XCTAssertEqual(decide(voiceOver: true).skipReason, .voiceOver)
        XCTAssertEqual(decide(alreadyPlayed: true).skipReason, .alreadyPlayed)
        XCTAssertEqual(decide(isFirstScene: false).skipReason, .secondaryScene)
    }

    private func decide(
        isUITesting: Bool = false,
        isActiveRecording: Bool = false,
        hasPendingRecordingRequest: Bool = false,
        openedFromURL: Bool = false,
        openedFromNotification: Bool = false,
        voiceOver: Bool = false,
        alreadyPlayed: Bool = false,
        isFirstScene: Bool = true
    ) -> LaunchIntroDecision {
        LaunchIntroGate.decide(
            isUITesting: isUITesting,
            isActiveRecording: isActiveRecording,
            hasPendingRecordingRequest: hasPendingRecordingRequest,
            openedFromURL: openedFromURL,
            openedFromNotification: openedFromNotification,
            voiceOver: voiceOver,
            alreadyPlayed: alreadyPlayed,
            isFirstScene: isFirstScene
        )
    }
}