import Foundation

/// Log severity for `DevLog` entries.
public enum DevLogLevel: String, Sendable {
    case info
    case warning
    case error

    var badge: String {
        switch self {
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERR"
        }
    }
}

/// Coarse subsystem tag for `DevLog` entries. Keep this list small and stable
/// so exported logs stay easy to filter/scan.
public enum DevLogCategory: String, Sendable, CaseIterable, Hashable {
    case lifecycle
    case bluetooth
    case recording
    case location
    case widget
    case tripDetail
    case general
}

/// Which process is writing a daily segment. App and widget never share an active file.
public enum DevLogProcessRole: String, Sendable {
    case app
    case widget
}

/// Milehound has no analytics or crash reporting (the app works fully offline).
/// Diagnostic lines stay on-device in dated App Group segments for 30 days, then
/// the user may choose Settings → Report a problem to mail a sanitized copy.
///
/// Do not log coordinates, addresses, place/vehicle names, user notes, or photos.
public final class DevLog: @unchecked Sendable {
    public static let shared = DevLog()

    public static let retentionDays = 30
    public static let maxBytes = 2 * 1024 * 1024
    public static let reportFileName = "milehound-debug.txt"

    private let queue = DispatchQueue(label: "com.milehound.devlog", qos: .utility)
    private let fileManager: FileManager
    private let now: () -> Date
    private let processRole: DevLogProcessRole
    private let logsDirectory: URL?

    public convenience init() {
        let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: RecordingControlBridge.appGroupSuiteName
        )?.appendingPathComponent("logs", isDirectory: true)
        self.init(
            directory: dir,
            processRole: Self.inferredProcessRole(),
            now: Date.init,
            fileManager: .default
        )
    }

    init(
        directory: URL?,
        processRole: DevLogProcessRole,
        now: @escaping () -> Date,
        fileManager: FileManager
    ) {
        self.logsDirectory = directory
        self.processRole = processRole
        self.now = now
        self.fileManager = fileManager
    }

    public func log(_ category: DevLogCategory, _ message: String, level: DevLogLevel = .info) {
        queue.async { [weak self] in
            guard let self else { return }
            let timestamp = Self.utcTimestampString(from: self.now())
            let line = "[\(timestamp)] [\(level.badge)] [\(category.rawValue)] \(message)\n"
            self.append(line)
        }
    }

    public func warning(_ category: DevLogCategory, _ message: String) {
        log(category, message, level: .warning)
    }

    public func error(_ category: DevLogCategory, _ message: String) {
        log(category, message, level: .error)
    }

    public func applyRetention() {
        queue.sync {
            applyRetentionLocked(force: true)
        }
    }

    /// Sanitized diagnostic text for a support mail. Applies retention first.
    public func sanitizedReportText() -> String {
        queue.sync {
            applyRetentionLocked(force: true)
            let raw = mergedLinesLocked().joined(separator: "\n")
            return DevLogSanitizer.sanitize(raw)
        }
    }

    /// Writes a temporary UTF-8 report. Caller must delete the file after share/mail dismiss.
    public func makeReportFile() throws -> URL {
        let text = sanitizedReportText()
        let url = fileManager.temporaryDirectory.appendingPathComponent(Self.reportFileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func clear() {
        queue.sync {
            guard let logsDirectory else { return }
            try? fileManager.removeItem(at: logsDirectory)
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            migrateLegacyFileLocked()
        }
    }

    private func append(_ line: String) {
        guard let logsDirectory, let data = line.data(using: .utf8) else { return }
        migrateLegacyFileLocked()
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
        applyRetentionLocked(force: false)

        let url = activeFileURL(in: logsDirectory)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        trimOwnFileIfNeededLocked(url)
    }

    private func applyRetentionLocked(force: Bool) {
        guard let logsDirectory else { return }
        migrateLegacyFileLocked()
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }

        let today = Self.utcDayString(from: now())
        let stampURL = logsDirectory.appendingPathComponent(".last-prune")
        let last = (try? String(contentsOf: stampURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !force, last == today { return }

        let cutoff = Self.utcDayString(from: now().addingTimeInterval(TimeInterval(-Self.retentionDays * 24 * 60 * 60)))
        for file in segmentFilesLocked() {
            guard let day = Self.day(fromSegmentName: file.lastPathComponent) else {
                try? fileManager.removeItem(at: file)
                continue
            }
            if day < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
        dropOldestClosedDaysUntilUnderCapLocked(today: today)
        try? today.write(to: stampURL, atomically: true, encoding: .utf8)
    }

    private func dropOldestClosedDaysUntilUnderCapLocked(today: String) {
        var files = segmentFilesLocked().sorted { $0.lastPathComponent < $1.lastPathComponent }
        while totalBytesLocked(files) > Self.maxBytes {
            guard let oldest = files.first(where: { Self.day(fromSegmentName: $0.lastPathComponent) != today })
                    ?? files.first else { break }
            try? fileManager.removeItem(at: oldest)
            files.removeAll { $0 == oldest }
        }
    }

    private func trimOwnFileIfNeededLocked(_ url: URL) {
        let files = segmentFilesLocked()
        guard totalBytesLocked(files) > Self.maxBytes else { return }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size > 0 else { return }
        guard let full = try? Data(contentsOf: url),
              let text = String(data: full, encoding: .utf8) else { return }
        let overflow = totalBytesLocked(files) - Self.maxBytes
        let keepBytes = max(0, full.count - overflow - (full.count / 4))
        let kept = Self.lineSafeSuffix(text, maxBytes: keepBytes)
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mergedLinesLocked() -> [String] {
        var lines: [String] = []
        for file in segmentFilesLocked().sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            lines.append(contentsOf: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        }
        return lines.sorted { lhs, rhs in
            timestampPrefix(lhs) < timestampPrefix(rhs)
        }
    }

    private func timestampPrefix(_ line: String) -> String {
        if line.first == "[", let close = line.firstIndex(of: "]") {
            return String(line[line.index(after: line.startIndex)..<close])
        }
        return line
    }

    private func segmentFilesLocked() -> [URL] {
        guard let logsDirectory,
              let names = try? fileManager.contentsOfDirectory(atPath: logsDirectory.path)
        else { return [] }
        return names.compactMap { name in
            guard name.hasPrefix("milehound-"), name.hasSuffix(".log") else { return nil }
            return logsDirectory.appendingPathComponent(name)
        }
    }

    private func totalBytesLocked(_ files: [URL]) -> Int {
        files.reduce(0) { sum, url in
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return sum + Int(size)
        }
    }

    private func activeFileURL(in directory: URL) -> URL {
        let day = Self.utcDayString(from: now())
        return directory.appendingPathComponent("milehound-\(day)-\(processRole.rawValue).log")
    }

    private func migrateLegacyFileLocked() {
        guard let logsDirectory else { return }
        let parent = logsDirectory.deletingLastPathComponent()
        let legacy = parent.appendingPathComponent("milehound-debug.log")
        if fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.removeItem(at: legacy)
        }
    }

    static func inferredProcessRole() -> DevLogProcessRole {
        let id = Bundle.main.bundleIdentifier ?? ""
        if id.contains("widget") { return .widget }
        return .app
    }

    static func utcTimestampString(from date: Date) -> String {
        let parts = utcParts(from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            parts.year, parts.month, parts.day,
            parts.hour, parts.minute, parts.second, parts.millisecond
        )
    }

    static func utcDayString(from date: Date) -> String {
        let parts = utcParts(from: date)
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    private static func utcParts(from date: Date) -> (
        year: Int, month: Int, day: Int,
        hour: Int, minute: Int, second: Int, millisecond: Int
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let millisecond = min(999, (components.nanosecond ?? 0) / 1_000_000)
        return (
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            millisecond
        )
    }

    static func day(fromSegmentName name: String) -> String? {
        // milehound-YYYY-MM-DD-app.log
        let parts = name.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        let day = "\(parts[1])-\(parts[2])-\(parts[3])"
        guard day.count == 10 else { return nil }
        return day
    }

    static func lineSafeSuffix(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        let data = Data(text.utf8)
        if data.count <= maxBytes { return text }
        let tail = data.suffix(maxBytes)
        var start = 0
        if let firstNewline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            start = tail.distance(from: tail.startIndex, to: firstNewline) + 1
        }
        let sliced = tail.dropFirst(start)
        return String(decoding: sliced, as: UTF8.self)
    }
}

enum DevLogSanitizer {
    static func sanitize(_ text: String) -> String {
        var result = text
        result.replace(#/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/#) { match in
            String(match.output.prefix(8))
        }
        result.replace(#/(?:file://)?(?:/Users|/var|/private|/tmp|/System)[^\s]+/#) { _ in "<path>" }
        result.replace(#/-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}/#) { _ in "<coord>" }
        result.replace(#/[\w.-]+\.(?:png|jpe?g|heic)/#.ignoresCase()) { _ in "<photo>" }
        return result
    }
}
