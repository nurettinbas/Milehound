import CoreGraphics
import Foundation

/// One amount found on a receipt.
struct ReceiptAmountCandidate: Equatable, Sendable, Identifiable {
    /// Exact value as printed (e.g. 1234.56).
    let value: Decimal
    /// The digits as they appeared on the receipt (e.g. `1.234,56`).
    let printed: String
    /// Union of the row's text boxes, normalized, top-left origin. Nil when the source had no geometry.
    let box: CGRect?
    /// Folded label that matched (`GENEL TOPLAM`, `TOTAL`, …). Nil for the largest-number fallback.
    let keyword: String?

    var id: String { "\(printed)|\(box.map { "\($0.minY)" } ?? "")" }

    /// Whole currency units, matching the expense amount field.
    var wholeUnits: Int {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    var hasFraction: Bool {
        value != Decimal(wholeUnits)
    }
}

struct ReceiptAmountScan: Equatable, Sendable {
    enum Confidence: Equatable, Sendable {
        /// Matched a total label (GENEL TOPLAM, ÖDENECEK, TOTAL…).
        case labeled
        /// No total label; the largest money-like number is only a guess.
        case guessed
    }

    let best: ReceiptAmountCandidate
    let alternates: [ReceiptAmountCandidate]
    let confidence: Confidence
}

/// Picks the payable total from recognized receipt text with fixed rules. No model is involved.
enum ReceiptAmountParser {
    /// Higher in the list wins. Matched against folded (ASCII, upper-case) row text.
    static let totalKeywords: [String] = [
        "GENEL TOPLAM",
        "ODENECEK TUTAR",
        "ODENECEK",
        "TOPLAM TUTAR",
        "GRAND TOTAL",
        "AMOUNT DUE",
        "TOTAL DUE",
        "TOPLAM",
        "TOTAL",
    ]

    /// Rows that carry money but are never the payable total.
    static let excludedKeywords: [String] = [
        "ARA TOPLAM",
        "ARATOPLAM",
        "SUBTOTAL",
        "SUB TOTAL",
        "TOPKDV",
        "TOP KDV",
        "TOPLAM KDV",
        "KDV",
        "VAT",
        "TAX",
        "PARA USTU",
        "PARAUSTU",
        "NAKIT",
        "CHANGE",
        "CASH",
        "INDIRIM",
        "DISCOUNT",
    ]

    static let maxAlternates = 4

    /// Amounts with exactly two decimals, optional thousands groups; never part of a date or longer number.
    private static let moneyPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[.,']\d{3})+|\d+)[.,](\d{2})(?![.,]?\d)"#
    )

    /// Rows carrying a total label may print whole amounts (`TOPLAM 450 TL`).
    private static let wholePattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[.,']\d{3})+|\d+)(?![.,]?\d)"#
    )

    // MARK: - Entry points

    static func parse(_ lines: [ReceiptTextLine]) -> ReceiptAmountScan? {
        parse(rows: groupIntoRows(lines))
    }

    /// Plain text, one receipt row per line. Used by tests and pasted text.
    static func parse(text: String) -> ReceiptAmountScan? {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { Row(text: String($0), box: nil) }
        return parse(rows: rows)
    }

    // MARK: - Rows

    struct Row: Equatable {
        var text: String
        var box: CGRect?
    }

    /// Vision often splits `TOPLAM` (left) and `*123,45` (right) into two observations on one row.
    static func groupIntoRows(_ lines: [ReceiptTextLine]) -> [Row] {
        let sorted = lines.sorted { $0.box.midY < $1.box.midY }
        var groups: [[ReceiptTextLine]] = []
        for line in sorted {
            if var last = groups.last,
               let anchor = last.first,
               sharesRow(anchor.box, line.box) {
                last.append(line)
                groups[groups.count - 1] = last
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return Row(text: ordered.map(\.text).joined(separator: " "), box: box)
        }
    }

    private static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let shorter = min(a.height, b.height)
        guard shorter > 0 else { return abs(a.midY - b.midY) < 0.005 }
        return overlap / shorter >= 0.5
    }

    // MARK: - Ranking

    private static func parse(rows: [Row]) -> ReceiptAmountScan? {
        var labeled: [(rank: Int, order: Int, candidate: ReceiptAmountCandidate)] = []
        var all: [ReceiptAmountCandidate] = []

        for (index, row) in rows.enumerated() {
            let folded = fold(row.text)
            // `TOPLAM (KDV DAHİL)` is the payable total, not a tax line.
            let taxFree = folded
                .replacingOccurrences(of: "KDV DAHIL", with: " ")
                .replacingOccurrences(of: "DAHIL KDV", with: " ")
            let excluded = containsKeyword(taxFree, from: excludedKeywords) != nil
            let keyword = excluded ? nil : containsKeyword(folded, from: totalKeywords)

            var amounts = moneyAmounts(in: row.text, box: row.box, keyword: keyword)
            if amounts.isEmpty, let keyword {
                amounts = wholeAmounts(in: row.text, box: row.box, keyword: keyword)
                // Label on one row, value printed on the next.
                if amounts.isEmpty, index + 1 < rows.count {
                    let next = rows[index + 1]
                    if containsKeyword(fold(next.text), from: excludedKeywords) == nil {
                        amounts = moneyAmounts(in: next.text, box: unionBox(row.box, next.box), keyword: keyword)
                    }
                }
            }

            if !excluded {
                all.append(contentsOf: amounts)
            }
            if let keyword, let rank = totalKeywords.firstIndex(of: keyword), let amount = amounts.last {
                labeled.append((rank, index, amount))
            }
        }

        let best: ReceiptAmountCandidate
        let confidence: ReceiptAmountScan.Confidence
        if let top = labeled.min(by: { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.order > rhs.order
        }) {
            best = top.candidate
            confidence = .labeled
        } else if let largest = all.max(by: { $0.value < $1.value }) {
            best = largest
            confidence = .guessed
        } else {
            return nil
        }

        var seen: Set<Decimal> = [best.value]
        var alternates: [ReceiptAmountCandidate] = []
        let others = (labeled.map(\.candidate) + all.sorted { $0.value > $1.value })
        for candidate in others where candidate.value > 0 && seen.insert(candidate.value).inserted {
            alternates.append(candidate)
            if alternates.count == maxAlternates { break }
        }
        return ReceiptAmountScan(best: best, alternates: alternates, confidence: confidence)
    }

    // MARK: - Number extraction

    private static func moneyAmounts(in text: String, box: CGRect?, keyword: String?) -> [ReceiptAmountCandidate] {
        let range = NSRange(text.startIndex..., in: text)
        return moneyPattern.matches(in: text, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 1), in: text),
                  let fraction = Range(match.range(at: 2), in: text),
                  let printed = Range(match.range, in: text) else { return nil }
            let digits = text[whole].filter(\.isNumber) + "." + text[fraction]
            guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return ReceiptAmountCandidate(value: value, printed: String(text[printed]), box: box, keyword: keyword)
        }
    }

    private static func wholeAmounts(in text: String, box: CGRect?, keyword: String) -> [ReceiptAmountCandidate] {
        let range = NSRange(text.startIndex..., in: text)
        return wholePattern.matches(in: text, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 1), in: text) else { return nil }
            let digits = text[whole].filter(\.isNumber)
            guard let value = Decimal(string: String(digits)), value > 0 else { return nil }
            return ReceiptAmountCandidate(value: value, printed: String(text[whole]), box: box, keyword: keyword)
        }
    }

    // MARK: - Text folding

    /// Upper-case ASCII so `Ödenecek`, `ÖDENECEK`, and `ODENECEK` match the same keyword.
    static func fold(_ text: String) -> String {
        let upper = text.uppercased(with: Locale(identifier: "tr_TR"))
        let ascii = upper
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "İ", with: "I")
            .replacingOccurrences(of: "ı", with: "I")
        let collapsed = ascii.unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
                ? Character(scalar)
                : " "
        }
        return String(collapsed)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func containsKeyword(_ folded: String, from keywords: [String]) -> String? {
        let padded = " \(folded) "
        return keywords.first { padded.contains(" \($0) ") }
    }

    private static func unionBox(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
        switch (a, b) {
        case let (a?, b?): return a.union(b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}
