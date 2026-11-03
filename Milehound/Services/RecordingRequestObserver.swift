import Foundation

final class RecordingRequestObserver {
    nonisolated(unsafe) static let shared = RecordingRequestObserver()
    nonisolated(unsafe) private static var stopHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var startHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var pauseHandler: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var resumeHandler: (@MainActor () -> Void)?

    var onStopRequested: (@MainActor () -> Void)? {
        get { Self.stopHandler }
        set { Self.stopHandler = newValue }
    }

    var onStartRequested: (@MainActor () -> Void)? {
        get { Self.startHandler }
        set { Self.startHandler = newValue }
    }

    var onPauseRequested: (@MainActor () -> Void)? {
        get { Self.pauseHandler }
        set { Self.pauseHandler = newValue }
    }

    var onResumeRequested: (@MainActor () -> Void)? {
        get { Self.resumeHandler }
        set { Self.resumeHandler = newValue }
    }

    private var isInstalled = false

    @MainActor
    static func handleStopRequestFromBackground() {
        stopHandler?()
    }

    @MainActor
    static func handleStartRequestFromBackground() {
        startHandler?()
    }

    @MainActor
    static func handlePauseRequestFromBackground() {
        pauseHandler?()
    }

    @MainActor
    static func handleResumeRequestFromBackground() {
        resumeHandler?()
    }

    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let observer = Unmanaged.passUnretained(self).toOpaque()

        RecordingControlBridge.registerDarwinStopObserver(observer: observer) { _, _, _, _, _ in
            dispatchRecordingStopRequestToMainActor()
        }

        RecordingControlBridge.registerDarwinStartObserver(observer: observer) { _, _, _, _, _ in
            dispatchRecordingStartRequestToMainActor()
        }

        RecordingControlBridge.registerDarwinPauseObserver(observer: observer) { _, _, _, _, _ in
            dispatchRecordingPauseRequestToMainActor()
        }

        RecordingControlBridge.registerDarwinResumeObserver(observer: observer) { _, _, _, _, _ in
            dispatchRecordingResumeRequestToMainActor()
        }
    }
}

private nonisolated func dispatchRecordingStopRequestToMainActor() {
    Task { @MainActor in
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        RecordingRequestObserver.handleStopRequestFromBackground()
    }
}

private nonisolated func dispatchRecordingStartRequestToMainActor() {
    Task { @MainActor in
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        RecordingRequestObserver.handleStartRequestFromBackground()
    }
}

private nonisolated func dispatchRecordingPauseRequestToMainActor() {
    Task { @MainActor in
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        RecordingRequestObserver.handlePauseRequestFromBackground()
    }
}

private nonisolated func dispatchRecordingResumeRequestToMainActor() {
    Task { @MainActor in
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        RecordingRequestObserver.handleResumeRequestFromBackground()
    }
}
