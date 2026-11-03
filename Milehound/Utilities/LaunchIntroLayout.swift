import CoreGraphics
import Foundation
import Observation

// MARK: - Timeline

/// Clocks for the cold-launch intro. Pure; the scene plays these on Core Animation.
struct LaunchIntroTimeline: Equatable {
    /// Launch color has become the theme plate; the picture has settled in.
    var enterEnd: TimeInterval
    /// Large run ends; the plate starts closing into the icon.
    var runEnd: TimeInterval
    /// Plate is the app icon.
    var closeEnd: TimeInterval
    var total: TimeInterval
    var allowsMotion: Bool
    /// Preferred display rate. Existing display links keep their own caps.
    var preferredFrameRate: Float

    static var standard: LaunchIntroTimeline {
        LaunchIntroTimeline(
            enterEnd: 0.28,
            runEnd: 0.91,
            closeEnd: 1.47,
            total: MilehoundMotion.launchIntroDuration,
            allowsMotion: true,
            preferredFrameRate: 120
        )
    }

    static var lowPower: LaunchIntroTimeline {
        LaunchIntroTimeline(
            enterEnd: 0.21,
            runEnd: 0.595,
            closeEnd: 0.98,
            total: MilehoundMotion.launchIntroLowPowerDuration,
            allowsMotion: true,
            preferredFrameRate: 60
        )
    }

    /// Still logo. No run, no close.
    static var reduceMotion: LaunchIntroTimeline {
        let duration = MilehoundMotion.launchIntroReduceMotionDuration
        return LaunchIntroTimeline(
            enterEnd: 0,
            runEnd: 0,
            closeEnd: 0,
            total: duration,
            allowsMotion: false,
            preferredFrameRate: 60
        )
    }

    /// Tap-to-skip. Fades out from wherever the intro is.
    static var skip: LaunchIntroTimeline {
        let duration = MilehoundMotion.launchIntroSkipDuration
        return LaunchIntroTimeline(
            enterEnd: 0,
            runEnd: 0,
            closeEnd: 0,
            total: duration,
            allowsMotion: false,
            preferredFrameRate: 120
        )
    }

    static func resolve(reduceMotion: Bool, lowPower: Bool) -> LaunchIntroTimeline {
        if reduceMotion { return .reduceMotion }
        if lowPower { return .lowPower }
        return .standard
    }
}

// MARK: - Hound rig

/// The icon’s hound cut into front and rear body, tail, and two-segment legs by
/// `scripts/export_launch_hound_parts.py`. Every part shares the source canvas, so drawn in the same
/// rect they rebuild the logo exactly. Joints are canvas pixels. The curves are the run cycle of
/// "Blackhound" (Julio Gonzalez, LottieFiles, Lottie Simple License) fitted by the same script,
/// mirrored to face right, phase-aligned so phase 0 is the stride pose nearest the logo. Rerun it and paste
/// `standard` if the hound art changes.
struct LaunchIntroHoundRig: Equatable {
    /// One loop per stride: `bias` plus the sum of `cosines[k] * cos(2π(k+1)φ) + sines[k] * sin(2π(k+1)φ)`.
    /// Offset from the logo pose in radians for rotations (positive is clockwise on screen),
    /// a fraction of the hound for moves.
    struct Curve: Equatable {
        var bias: CGFloat
        var cosines: [CGFloat]
        var sines: [CGFloat]

        static let still = Curve(bias: 0, cosines: [], sines: [])

        func value(at phase: CGFloat) -> CGFloat {
            var sum = bias
            for (index, (a, b)) in zip(cosines, sines).enumerated() {
                let angle = 2 * .pi * CGFloat(index + 1) * phase
                sum += a * cos(angle) + b * sin(angle)
            }
            return sum
        }
    }

    /// A part that turns around `joint`, carrying its children. `behind` draw under the part, `front` over it.
    struct Bone: Equatable {
        var asset: String
        var joint: CGPoint
        var swing: Curve
        var behind: [Bone] = []
        var front: [Bone] = []

        var all: [Bone] {
            [self] + (behind + front).flatMap(\.all)
        }
    }

    var canvas: CGSize
    /// Front body; pitches the whole hound. The rear body flexes at the spine under it.
    var torso: Bone
    /// Vertical lift, fraction of the hound’s height. Negative is up.
    var bob: Curve
    var stride: TimeInterval

    var bones: [Bone] { torso.all }

    static let standard = LaunchIntroHoundRig(
        canvas: CGSize(width: 738, height: 410),
        torso: Bone(
            asset: "MilehoundHoundFront",
            joint: CGPoint(x: 370.0, y: 180.0),
            swing: Curve(bias: -0.0639, cosines: [0.0580, 0.0038, 0.0020, 0.0001], sines: [0.0026, 0.0006, 0.0015, -0.0003]),
            behind: [
                Bone(
                    asset: "MilehoundHoundForeFoldUpper",
                    joint: CGPoint(x: 515.5, y: 221.0),
                    swing: Curve(bias: 0.1592, cosines: [0.5030, 0.0348, 0.0532, -0.0323], sines: [0.5225, -0.0995, 0.0351, -0.0268]),
                    front: [
                        Bone(asset: "MilehoundHoundForeFoldLower", joint: CGPoint(x: 520.8, y: 296.8), swing: Curve(bias: -0.7239, cosines: [0.1434, -0.1011, 0.0557, -0.0025], sines: [0.5999, 0.0228, 0.1121, 0.0090]))
                    ]
                ),
                Bone(
                    asset: "MilehoundHoundRear",
                    joint: CGPoint(x: 350.0, y: 120.0),
                    swing: Curve(bias: 0.1040, cosines: [-0.0898, -0.0038, -0.0081, -0.0023], sines: [-0.1070, -0.0285, -0.0075, -0.0016]),
                    behind: [
                        Bone(asset: "MilehoundHoundTail", joint: CGPoint(x: 165.0, y: 190.0), swing: Curve(bias: 0.0000, cosines: [-0.1076, 0.0000, 0.0000, 0.0000], sines: [-0.0531, 0.0000, -0.0000, 0.0000])),
                        Bone(
                            asset: "MilehoundHoundHindTuckUpper",
                            joint: CGPoint(x: 315.5, y: 168.0),
                            swing: Curve(bias: 0.1702, cosines: [-0.5974, -0.1044, 0.0277, 0.0052], sines: [-0.2920, -0.0773, 0.0090, -0.0175]),
                            front: [
                                Bone(asset: "MilehoundHoundHindTuckLower", joint: CGPoint(x: 285.0, y: 296.4), swing: Curve(bias: 0.6310, cosines: [-0.2798, -0.0654, -0.0041, -0.0015], sines: [-0.3942, 0.0855, 0.0418, -0.0330]))
                            ]
                        )
                    ],
                    front: [
                        Bone(
                            asset: "MilehoundHoundHindReachUpper",
                            joint: CGPoint(x: 242.5, y: 200.0),
                            swing: Curve(bias: -0.4549, cosines: [-0.2070, 0.1230, -0.0457, -0.0035], sines: [-0.6544, 0.0542, 0.0318, -0.0389]),
                            front: [
                                Bone(asset: "MilehoundHoundHindReachLower", joint: CGPoint(x: 138.7, y: 292.7), swing: Curve(bias: 0.0928, cosines: [-0.4846, -0.1122, -0.0053, 0.0211], sines: [-0.2630, -0.0115, 0.0044, 0.0064]))
                            ]
                        )
                    ]
                )
            ],
            front: [
                Bone(
                    asset: "MilehoundHoundForeReachUpper",
                    joint: CGPoint(x: 493.0, y: 204.0),
                    swing: Curve(bias: -0.8392, cosines: [0.6988, -0.0191, -0.0826, 0.0411], sines: [0.3286, 0.2011, -0.0801, 0.0074]),
                    front: [
                        Bone(asset: "MilehoundHoundForeReachLower", joint: CGPoint(x: 396.5, y: 346.5), swing: Curve(bias: 0.2582, cosines: [-0.2755, -0.2442, -0.0376, 0.0003], sines: [0.3676, -0.1271, -0.1023, -0.0786]))
                    ]
                )
            ]
        ),
        bob: Curve(bias: 0.0000, cosines: [-0.0000, -0.0122, 0.0000, 0.0000], sines: [-0.0000, -0.0159, 0.0000, -0.0000]),
        stride: MilehoundMotion.launchIntroGallopStride
    )

    /// Offset from the logo pose at `time`. The envelope holds it at zero at the start and from `closeEnd`.
    func offset(_ curve: Curve, at time: TimeInterval, timeline: LaunchIntroTimeline) -> CGFloat {
        guard stride > 0 else { return 0 }
        let phase = CGFloat(time / stride)
        return Self.envelope(at: time, timeline: timeline) * curve.value(at: phase)
    }

    /// 0 before the picture appears, eases to 1 as it settles, holds through the run,
    /// then dies out as (1 - x)² to 0 at `closeEnd`, like the stopwatch rock.
    static func envelope(at time: TimeInterval, timeline: LaunchIntroTimeline) -> CGFloat {
        guard time > 0, time < timeline.closeEnd else { return 0 }
        if time < timeline.enterEnd {
            let x = CGFloat(time / timeline.enterEnd)
            return x * x * (3 - 2 * x)
        }
        if time <= timeline.runEnd { return 1 }
        let closing = timeline.closeEnd - timeline.runEnd
        guard closing > 0 else { return 0 }
        let x = CGFloat((time - timeline.runEnd) / closing)
        return pow(1 - x, 2)
    }
}

// MARK: - Gate

enum LaunchIntroSkipReason: Equatable {
    case uiTest
    case activeRecording
    case pendingRecordingRequest
    case openedFromURL
    case notificationTap
    case voiceOver
    case alreadyPlayed
    case secondaryScene
}

struct LaunchIntroDecision: Equatable {
    var plays: Bool
    var skipReason: LaunchIntroSkipReason?

    static func play() -> LaunchIntroDecision {
        LaunchIntroDecision(plays: true, skipReason: nil)
    }

    static func skip(_ reason: LaunchIntroSkipReason) -> LaunchIntroDecision {
        LaunchIntroDecision(plays: false, skipReason: reason)
    }
}

enum LaunchIntroGate {
    static func decide(
        isUITesting: Bool,
        isActiveRecording: Bool,
        hasPendingRecordingRequest: Bool,
        openedFromURL: Bool,
        openedFromNotification: Bool,
        voiceOver: Bool,
        alreadyPlayed: Bool,
        isFirstScene: Bool
    ) -> LaunchIntroDecision {
        if isUITesting { return .skip(.uiTest) }
        if alreadyPlayed { return .skip(.alreadyPlayed) }
        if !isFirstScene { return .skip(.secondaryScene) }
        if isActiveRecording { return .skip(.activeRecording) }
        if hasPendingRecordingRequest { return .skip(.pendingRecordingRequest) }
        if openedFromURL { return .skip(.openedFromURL) }
        if openedFromNotification { return .skip(.notificationTap) }
        if voiceOver { return .skip(.voiceOver) }
        return .play()
    }
}

/// Process-wide cold-launch latch. The first scene may play once; later scenes and
/// foreground resumes do not. URL and notification flags are set before the first frame
/// when UIKit delivers them with the scene connection.
@MainActor
@Observable
final class LaunchIntroSession {
    static let shared = LaunchIntroSession()

    private(set) var didFinish = false
    /// True only when the hound intro actually ran (onboarding then skips its own drive-in).
    private(set) var playedIntro = false
    /// Set as soon as this process decides to play, before the overlay's first frame.
    private(set) var coversFirstScreen = false
    private(set) var openedFromURL = false
    private(set) var openedFromNotification = false
    private var didClaimScene = false

    func noteURLOpen() {
        openedFromURL = true
    }

    func noteNotificationTap() {
        openedFromNotification = true
    }

    /// The first caller in the process owns the intro.
    func claimFirstScene() -> Bool {
        if didClaimScene { return false }
        didClaimScene = true
        return true
    }

    func markCovering() {
        coversFirstScreen = true
    }

    func markPlayed() {
        playedIntro = true
        didFinish = true
    }

    func markSkipped() {
        didFinish = true
    }
}
