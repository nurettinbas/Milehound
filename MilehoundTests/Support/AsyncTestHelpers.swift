import XCTest

@MainActor
enum AsyncTestHelpers {
    static func waitFor(
        timeout: TimeInterval = 8,
        pollInterval: TimeInterval = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .seconds(pollInterval))
        }
        XCTFail("Condition not met within \(timeout)s", file: file, line: line)
    }
}
