import SwiftUI
import XCTest
@testable import Milehound

@MainActor
final class AchievementShareRendererTests: XCTestCase {
    func testSharePosterIsStorySizedAndDiffersByBadge() throws {
        let unlocked = Date(timeIntervalSince1970: 1_700_000_000)
        let first = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: unlocked,
            needsCelebration: false
        )
        let km = AchievementDisplay(
            id: .distance100,
            currentValue: 100_000,
            unlockedAt: unlocked,
            needsCelebration: false
        )
        let firstImage = AchievementShareRenderer.image(for: first, palette: .gold, scheme: .light)
        let kmImage = AchievementShareRenderer.image(for: km, palette: .gold, scheme: .light)
        XCTAssertEqual(
            firstImage.size.width * firstImage.scale,
            AchievementShareRenderer.pixelSize.width,
            accuracy: 2
        )
        XCTAssertEqual(
            firstImage.size.height * firstImage.scale,
            AchievementShareRenderer.pixelSize.height,
            accuracy: 2
        )
        let firstData = try XCTUnwrap(SocialImageShare.jpegData(from: firstImage))
        let kmData = try XCTUnwrap(SocialImageShare.jpegData(from: kmImage))
        XCTAssertGreaterThan(firstData.count, 4_000)
        XCTAssertEqual(Array(firstData.prefix(3)), [0xFF, 0xD8, 0xFF])
        XCTAssertNotEqual(firstData, kmData)
    }

    func testCaptionIncludesTitleAndBrand() {
        let item = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: Date(timeIntervalSince1970: 1_700_000_000),
            needsCelebration: false
        )
        let caption = AchievementShareRenderer.caption(for: item)
        XCTAssertTrue(caption.contains(L10n.string(item.id.titleKey)))
        XCTAssertTrue(caption.contains("Milehound"))
        XCTAssertTrue(caption.contains(L10n.string("premium.achievements.unlocked")))
    }

    func testGalleryShareSlotMatchesCompactHitTarget() {
        XCTAssertEqual(AchievementGalleryTokens.shareSlotHeight, 44)
        XCTAssertLessThan(AchievementGalleryTokens.cardHeight, 220)
    }
}
