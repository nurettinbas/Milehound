import XCTest
@testable import Milehound

final class SupportMailTests: XCTestCase {
    func testTurkishUIOpensTheKVKKNotice() {
        XCTAssertEqual(
            SupportMail.privacyPolicyURL(preferredLocalizations: ["tr"]).lastPathComponent,
            "PRIVACY_TR.md"
        )
        XCTAssertEqual(
            SupportMail.privacyPolicyURL(preferredLocalizations: ["tr-TR", "en"]),
            SupportMail.privacyPolicyTurkishURL
        )
    }

    func testOtherLanguagesOpenTheEnglishPolicy() {
        for languages in [["en"], ["en-GB", "tr"], ["de"], []] {
            XCTAssertEqual(
                SupportMail.privacyPolicyURL(preferredLocalizations: languages),
                SupportMail.privacyPolicyEnglishURL,
                "\(languages)"
            )
        }
    }

    func testPolicyLinksAreHTTPS() {
        for url in [SupportMail.privacyPolicyEnglishURL, SupportMail.privacyPolicyTurkishURL, SupportMail.supportPageURL] {
            XCTAssertEqual(url.scheme, "https")
        }
    }
}
