import XCTest
@testable import Milehound

final class DevLogTests: XCTestCase {
    private var directory: URL!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("devlog-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testKeepsLastThirtyDaysAndDropsOlder() {
        let now = date(2026, 9, 7, hour: 12)
        writeSegment(day: "2026-08-07", role: .app, line: "old")
        writeSegment(day: "2026-08-08", role: .app, line: "kept-edge")
        writeSegment(day: "2026-09-07", role: .app, line: "today")

        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.applyRetention()

        XCTAssertFalse(FileManager.default.fileExists(atPath: segmentURL(day: "2026-08-07", role: .app).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentURL(day: "2026-08-08", role: .app).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentURL(day: "2026-09-07", role: .app).path))
    }

    func testUTCDayBoundaryIgnoresLocalTimezone() {
        // 2026-09-07 00:30 UTC is still 2026-09-06 evening in UTC-5.
        let now = date(2026, 9, 7, hour: 0, minute: 30)
        writeSegment(day: "2026-08-07", role: .app, line: "would-keep-if-local")
        writeSegment(day: "2026-08-08", role: .app, line: "utc-keep")

        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.applyRetention()

        XCTAssertFalse(FileManager.default.fileExists(atPath: segmentURL(day: "2026-08-07", role: .app).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentURL(day: "2026-08-08", role: .app).path))
    }

    func testDropsUndatedLegacyAndMalformedSegments() {
        let now = date(2026, 9, 7, hour: 12)
        let parent = directory.deletingLastPathComponent()
        let legacy = parent.appendingPathComponent("milehound-debug.log")
        try? "legacy".write(to: legacy, atomically: true, encoding: .utf8)
        try? "bad".write(
            to: directory.appendingPathComponent("milehound-noday-app.log"),
            atomically: true,
            encoding: .utf8
        )

        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.applyRetention()

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("milehound-noday-app.log").path
            )
        )
    }

    func testMergesAppAndWidgetSegmentsInTimestampOrder() {
        let now = date(2026, 9, 7, hour: 12)
        writeSegment(
            day: "2026-09-07",
            role: .widget,
            line: "[2026-09-07T10:00:00.000Z] [INFO] [widget] later"
        )
        writeSegment(
            day: "2026-09-07",
            role: .app,
            line: "[2026-09-07T09:00:00.000Z] [INFO] [recording] earlier"
        )

        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        let report = log.sanitizedReportText()
        let earlier = report.range(of: "earlier")?.lowerBound
        let later = report.range(of: "later")?.lowerBound
        XCTAssertNotNil(earlier)
        XCTAssertNotNil(later)
        XCTAssertLessThan(earlier!, later!)
    }

    func testDropsOldestClosedDaysWhenOverTwoMegabytes() {
        let now = date(2026, 9, 7, hour: 12)
        writeSegment(day: "2026-08-20", role: .app, line: String(repeating: "a", count: 1_500_000))
        writeSegment(day: "2026-09-07", role: .app, line: String(repeating: "b", count: 1_000_000))

        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.applyRetention()

        XCTAssertFalse(FileManager.default.fileExists(atPath: segmentURL(day: "2026-08-20", role: .app).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentURL(day: "2026-09-07", role: .app).path))
    }

    func testSanitizerRedactsUUIDPathCoordinateAndPhoto() {
        let uuid = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let raw = """
        Trip started: id=\(uuid) file=car.png at 41.00820000, 28.97840000 path=/Users/nurettin/Documents/log.txt
        """
        let sanitized = DevLogSanitizer.sanitize(raw)
        XCTAssertFalse(sanitized.contains(uuid))
        XCTAssertTrue(sanitized.contains("aaaaaaaa"))
        XCTAssertTrue(sanitized.contains("<path>"))
        XCTAssertTrue(sanitized.contains("<coord>"))
        XCTAssertFalse(sanitized.contains("car.png"))
        XCTAssertTrue(sanitized.contains("<photo>"))
    }

    func testLineSafeSuffixDoesNotSplitUTF8() {
        let café = "café\n" + String(repeating: "x\n", count: 20)
        let trimmed = DevLog.lineSafeSuffix(café, maxBytes: 12)
        XCTAssertFalse(trimmed.contains("\u{FFFD}"))
        XCTAssertTrue(trimmed.hasSuffix("\n") || trimmed.allSatisfy { $0 == "x" || $0 == "\n" })
    }

    func testMakeReportFileIsDeletedByCaller() throws {
        let now = date(2026, 9, 7, hour: 12)
        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.log(.recording, "ok")
        // Flush the utility queue.
        log.applyRetention()
        let url = try log.makeReportFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, DevLog.reportFileName)
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSanitizedReportDoesNotContainCoordinateNameOrNote() {
        let now = date(2026, 9, 7, hour: 12)
        let log = DevLog(directory: directory, processRole: .app, now: { now }, fileManager: .default)
        log.log(.recording, "session start trip=abcd1234 auth=always bgGPS=true")
        log.applyRetention()
        let report = log.sanitizedReportText()
        XCTAssertFalse(report.contains("latitude"))
        XCTAssertFalse(report.contains("longitude"))
        XCTAssertFalse(report.contains("Home"))
        XCTAssertFalse(report.contains("note="))
    }

    private func writeSegment(day: String, role: DevLogProcessRole, line: String) {
        let url = segmentURL(day: day, role: role)
        let body = line.hasSuffix("\n") ? line : line + "\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func segmentURL(day: String, role: DevLogProcessRole) -> URL {
        directory.appendingPathComponent("milehound-\(day)-\(role.rawValue).log")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
