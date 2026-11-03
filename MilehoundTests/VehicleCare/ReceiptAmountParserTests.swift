import CoreGraphics
import UIKit
import XCTest
@testable import Milehound

final class ReceiptTextRecognizerTests: XCTestCase {
    func testRenderedReceiptReadsTotalOnDevice() async throws {
        let rows: [(String, String)] = [
            ("OPET AKARYAKIT", ""),
            ("KURSUNSUZ 95", "*1.491,75"),
            ("TOPKDV", "*248,63"),
            ("TOPLAM", "*1.491,75"),
        ]
        let size = CGSize(width: 900, height: 700)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.monospacedSystemFont(ofSize: 44, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            for (index, row) in rows.enumerated() {
                let y = 80 + CGFloat(index) * 140
                (row.0 as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attributes)
                let valueWidth = (row.1 as NSString).size(withAttributes: attributes).width
                (row.1 as NSString).draw(at: CGPoint(x: size.width - 60 - valueWidth, y: y), withAttributes: attributes)
            }
        }

        let lines = try await ReceiptTextRecognizer.recognize(image)
        XCTAssertFalse(lines.isEmpty)
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(lines), "Recognized: \(lines.map(\.text))")
        XCTAssertEqual(scan.confidence, .labeled)
        XCTAssertEqual(scan.best.value, Decimal(string: "1491.75"))
        let box = try XCTUnwrap(scan.best.box)
        XCTAssertGreaterThan(box.minY, 0.6, "TOPLAM row is in the bottom part of the image")
    }
}

final class ReceiptAmountParserTests: XCTestCase {
    func testTurkishFuelReceiptPicksToplamNotKdv() throws {
        let text = """
        OPET AKARYAKIT
        TARIH: 12.10.2026 SAAT: 14:35
        KURSUNSUZ 95 32,50 LT X 45,90
        *1.491,75
        TOPKDV *248,63
        TOPLAM *1.491,75
        KREDI KARTI *1.491,75
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.confidence, .labeled)
        XCTAssertEqual(scan.best.value, Decimal(string: "1491.75"))
        XCTAssertEqual(scan.best.wholeUnits, 1_492)
        XCTAssertEqual(scan.best.printed, "1.491,75")
        XCTAssertTrue(scan.best.hasFraction)
    }

    func testGenelToplamBeatsAraToplam() throws {
        let text = """
        ARA TOPLAM 2.000,00
        INDIRIM -150,00
        KDV %20 370,00
        GENEL TOPLAM 2.220,00
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.best.value, Decimal(2_220))
        XCTAssertEqual(scan.best.keyword, "GENEL TOPLAM")
        XCTAssertFalse(scan.best.hasFraction)
    }

    func testOdenecekWithTurkishLettersAndLowercase() throws {
        let text = """
        Servis işçilik 1.250,00
        Yağ filtresi 480,00
        Ödenecek Tutar: 1.730,00 TL
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.best.value, Decimal(1_730))
        XCTAssertEqual(scan.best.keyword, "ODENECEK TUTAR")
    }

    func testToplamKdvDahilIsTheTotal() throws {
        let text = """
        TOPLAM KDV 41,67
        TOPLAM (KDV DAHİL) 250,00
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.best.value, Decimal(250))
    }

    func testEnglishSeparatorsAndAmountDue() throws {
        let text = """
        Subtotal 1,180.00
        Tax 94.40
        Amount Due $1,274.40
        Cash 1,300.00
        Change 25.60
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.best.value, Decimal(string: "1274.40"))
        XCTAssertEqual(scan.best.wholeUnits, 1_274)
    }

    func testLabelOnOneRowValueOnNext() throws {
        let text = """
        GENEL TOPLAM
        *845,90
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.confidence, .labeled)
        XCTAssertEqual(scan.best.value, Decimal(string: "845.90"))
    }

    func testWholeAmountOnLabeledRow() throws {
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: "TOPLAM 450 TL"))
        XCTAssertEqual(scan.best.value, Decimal(450))
    }

    func testNoKeywordFallsBackToLargestAsGuess() throws {
        let text = """
        Lastik montaj 300,00
        Balans 150,00
        Supap 40,00
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.confidence, .guessed)
        XCTAssertEqual(scan.best.value, Decimal(300))
        XCTAssertEqual(scan.alternates.map(\.value), [Decimal(150), Decimal(40)])
    }

    func testDatesTimesAndPlainNumbersAreNotAmounts() {
        let text = """
        12.10.2026 14:35
        FIS NO: 0042
        Z NO 1234
        """
        XCTAssertNil(ReceiptAmountParser.parse(text: text))
    }

    func testAlternatesAreDistinctAndCapped() throws {
        let text = """
        A 10,00
        B 20,00
        C 30,00
        D 40,00
        E 50,00
        F 60,00
        TOPLAM 210,00
        """
        let scan = try XCTUnwrap(ReceiptAmountParser.parse(text: text))
        XCTAssertEqual(scan.best.value, Decimal(210))
        XCTAssertEqual(scan.alternates.count, ReceiptAmountParser.maxAlternates)
        XCTAssertFalse(scan.alternates.contains { $0.value == scan.best.value })
    }

    func testVisionRowsAreGroupedAndKeepGeometry() throws {
        let lines = [
            ReceiptTextLine(text: "TOPLAM", box: CGRect(x: 0.08, y: 0.70, width: 0.2, height: 0.03)),
            ReceiptTextLine(text: "*1.491,75", box: CGRect(x: 0.65, y: 0.705, width: 0.25, height: 0.028)),
            ReceiptTextLine(text: "TOPKDV", box: CGRect(x: 0.08, y: 0.65, width: 0.2, height: 0.03)),
            ReceiptTextLine(text: "*248,63", box: CGRect(x: 0.65, y: 0.65, width: 0.2, height: 0.03)),
        ]
        let rows = ReceiptAmountParser.groupIntoRows(lines)
        XCTAssertEqual(rows.map(\.text), ["TOPKDV *248,63", "TOPLAM *1.491,75"])

        let scan = try XCTUnwrap(ReceiptAmountParser.parse(lines))
        XCTAssertEqual(scan.best.value, Decimal(string: "1491.75"))
        let box = try XCTUnwrap(scan.best.box)
        XCTAssertEqual(box.minX, 0.08, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 0.90, accuracy: 0.001)
    }

    func testFoldNormalizesTurkishLetters() {
        XCTAssertEqual(ReceiptAmountParser.fold("Ödenecek Tutar:"), "ODENECEK TUTAR")
        XCTAssertEqual(ReceiptAmountParser.fold("GENEL TOPLAM*"), "GENEL TOPLAM")
        XCTAssertEqual(ReceiptAmountParser.fold("Nakit / para üstü"), "NAKIT PARA USTU")
        XCTAssertEqual(ReceiptAmountParser.fold("İndirim ı"), "INDIRIM I")
    }
}
