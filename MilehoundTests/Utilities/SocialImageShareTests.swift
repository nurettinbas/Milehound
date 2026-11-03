import UIKit
import XCTest
@testable import Milehound

@MainActor
final class SocialImageShareTests: XCTestCase {
    func testJPEGFileHasMagicBytesAndJpgExtension() throws {
        let url = try SocialImageShare.writeTemporaryJPEG(from: Self.swatch())
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension.lowercased(), "jpg")
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 32)
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
    }

    func testEmptyImageFailsJPEGExport() {
        XCTAssertThrowsError(try SocialImageShare.writeTemporaryJPEG(from: UIImage())) { error in
            XCTAssertEqual(error as? SocialImageShareError, .encodeFailed)
        }
    }

    func testCaptionPlaceholderIsNotAString() {
        let source = SocialImageShareCaptionSource(caption: "Year in review · 2026")
        let placeholder = source.activityViewControllerPlaceholderItem(Self.dummyController())
        XCTAssertFalse(placeholder is String)
        XCTAssertFalse(placeholder is NSString)
    }

    func testCaptionIsOmittedForInstagramAndFacebook() {
        let source = SocialImageShareCaptionSource(caption: "Home → Work")
        let controller = Self.dummyController()
        let instagram = UIActivity.ActivityType("com.burbn.instagram.shareextension")
        let facebook = UIActivity.ActivityType("com.facebook.Facebook.ShareExtension")
        XCTAssertTrue(SocialImageShare.omitsCaption(for: instagram))
        XCTAssertTrue(SocialImageShare.omitsCaption(for: facebook))
        XCTAssertNil(source.activityViewController(controller, itemForActivityType: instagram))
        XCTAssertNil(source.activityViewController(controller, itemForActivityType: facebook))
    }

    func testCaptionIsKeptForMessagesMailAndWhatsApp() {
        let caption = "Home → Work"
        let source = SocialImageShareCaptionSource(caption: caption)
        let controller = Self.dummyController()
        let whatsapp = UIActivity.ActivityType("net.whatsapp.WhatsApp.ShareExtension")
        XCTAssertFalse(SocialImageShare.omitsCaption(for: .message))
        XCTAssertFalse(SocialImageShare.omitsCaption(for: .mail))
        XCTAssertFalse(SocialImageShare.omitsCaption(for: whatsapp))
        XCTAssertEqual(
            source.activityViewController(controller, itemForActivityType: .message) as? String,
            caption
        )
        XCTAssertEqual(
            source.activityViewController(controller, itemForActivityType: .mail) as? String,
            caption
        )
        XCTAssertEqual(
            source.activityViewController(controller, itemForActivityType: whatsapp) as? String,
            caption
        )
    }

    func testPayloadIncludesCaptionSourceOnlyWhenCaptionExists() throws {
        let withCaption = try SocialImageShare.makePayload(image: Self.swatch(), caption: "Milehound")
        XCTAssertEqual(withCaption.activityItems.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: withCaption.fileURL.path))
        withCaption.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: withCaption.fileURL.path))

        let imageOnly = try SocialImageShare.makePayload(image: Self.swatch(), caption: nil)
        defer { imageOnly.cleanup() }
        XCTAssertEqual(imageOnly.activityItems.count, 1)

        let blankCaption = try SocialImageShare.makePayload(image: Self.swatch(), caption: "")
        defer { blankCaption.cleanup() }
        XCTAssertEqual(blankCaption.activityItems.count, 1)
    }

    private static func swatch() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func dummyController() -> UIActivityViewController {
        UIActivityViewController(activityItems: [""], applicationActivities: nil)
    }
}
