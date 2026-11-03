import AVFoundation
import UIKit
import XCTest
@testable import Milehound

/// Locks brand asset sizes and recording cue codecs so a 1024 logo / PCM CAF cannot sneak back in.
@MainActor
final class BundleBrandAssetTests: XCTestCase {
    func testMilehoundLogoIsExactly512Pixels() {
        let image = UIImage(named: "MilehoundLogo")
        XCTAssertNotNil(image)
        let edge = Int(round((image?.size.width ?? 0) * (image?.scale ?? 0)))
        XCTAssertEqual(edge, 512)
        let height = Int(round((image?.size.height ?? 0) * (image?.scale ?? 0)))
        XCTAssertEqual(height, 512)
    }

    func testMilehoundHoundStillLoads() {
        XCTAssertNotNil(UIImage(named: "MilehoundHound"))
    }

    func testLaunchHoundPartsShareTheHoundCanvas() throws {
        let hound = try XCTUnwrap(UIImage(named: "MilehoundHound")?.cgImage)
        let rig = LaunchIntroHoundRig.standard
        XCTAssertEqual(CGFloat(hound.width), rig.canvas.width)
        XCTAssertEqual(CGFloat(hound.height), rig.canvas.height)
        for name in rig.bones.map(\.asset) {
            let part = try XCTUnwrap(UIImage(named: name)?.cgImage, name)
            XCTAssertEqual(part.width, hound.width, name)
            XCTAssertEqual(part.height, hound.height, name)
        }
        XCTAssertNotNil(LaunchIntroHoundParts.load())
    }

    func testThemedLogoSkyLightIsPrimaryAsset() {
        let sky = MilehoundThemedLogo.image(palette: .sky, scheme: .light)
        let sand = MilehoundThemedLogo.image(palette: .sand, scheme: .light)
        XCTAssertNotNil(sky)
        XCTAssertNotNil(sand)
        XCTAssertEqual(sky?.size, sand?.size)
        XCTAssertNotEqual(sky, sand)
    }

    func testThemedLogoOrangeLightDiffersFromDark() {
        let light = MilehoundThemedLogo.image(palette: .orange, scheme: .light)
        let dark = MilehoundThemedLogo.image(palette: .orange, scheme: .dark)
        XCTAssertNotNil(light)
        XCTAssertNotNil(dark)
        XCTAssertNotEqual(light, dark)
    }

    func testRecordingStartSoundIsCompactAACInCAF() throws {
        try assertRecordingCue(
            resource: "trip_start",
            expectedDuration: 1.90
        )
    }

    func testRecordingStopSoundIsCompactAACInCAF() throws {
        try assertRecordingCue(
            resource: "trip_stop",
            expectedDuration: 1.65
        )
    }

    private func assertRecordingCue(resource: String, expectedDuration: TimeInterval) throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: resource, withExtension: "caf"),
            "Missing \(resource).caf in app bundle"
        )
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = try XCTUnwrap(attrs[.size] as? NSNumber).intValue
        XCTAssertLessThan(bytes, 80 * 1024, "\(resource).caf should stay under 80 KB (got \(bytes))")

        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(player.duration, expectedDuration, accuracy: 0.08)
    }
}
