import AudioToolbox
import AVFoundation

enum MilehoundSounds {
    static func recordingStarted() {
        schedule("trip_start")
    }

    static func recordingStopped() {
        schedule("trip_stop")
    }

    private static func schedule(_ name: String) {
        let resource = name
        Task { @MainActor in
            guard AppSettings.shared.recordingSoundsEnabled else { return }
            // The block that touches the session is built inside `enqueue`, which is
            // not main-actor isolated. A closure formed in this task would hop back
            // to the main thread and trip the synchronous `setActive` hang warning.
            SoundEngine.shared.enqueue(resource)
        }
    }
}

/// Recording cues use `.playback` + `.mixWithOthers` so they play on mute and
/// do not interrupt Music or CarPlay. iOS 27 logs a hang if `setActive` runs
/// on the main thread; `AVAudioPlayer.play()` does that, so cues go through
/// AudioQueue after the asynchronous activate API.
private final class SoundEngine: @unchecked Sendable {
    static let shared = SoundEngine()

    private let queue = DispatchQueue(
        label: "app.milehound.sounds",
        qos: .userInitiated,
        target: DispatchQueue.global(qos: .userInitiated)
    )

    private var sessionReady = false
    private var activating = false
    private var pending: [String] = []
    private var live: [CueClip] = []

    func enqueue(_ name: String) {
        queue.async { [self] in
            self.perform(name)
        }
    }

    private func perform(_ name: String) {
        if Thread.isMainThread {
            enqueue(name)
            return
        }
        if sessionReady {
            play(name)
            return
        }
        pending.append(name)
        guard !activating else { return }
        activating = true
        activateThenPlay()
    }

    private func activateThenPlay() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            finish(false)
            return
        }

        // `AVAudioSession.activate` is an iOS 27 SDK symbol. Xcode 26.5 cannot see it,
        // so the shim calls it only when that SDK is present.
        if MilehoundActivateAudioSessionIfAvailable({ [self] activated in
            self.enqueueFinish(activated)
        }) {
            return
        }
        let activated: Bool
        do {
            try session.setActive(true)
            activated = true
        } catch {
            activated = false
        }
        finish(activated)
    }

    private func enqueueFinish(_ activated: Bool) {
        queue.async { [self] in
            self.finish(activated)
        }
    }

    private func finish(_ activated: Bool) {
        activating = false
        let names = pending
        pending.removeAll()
        guard activated else { return }
        sessionReady = true
        for name in names {
            play(name)
        }
    }

    private func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        let clip = CueClip()
        guard clip.open(url: url) else { return }
        clip.onFinished = { [weak self, weak clip] in
            guard let self, let clip else { return }
            self.queue.async {
                clip.shutdown()
                self.live.removeAll { $0 === clip }
            }
        }
        live.append(clip)
        clip.start()
    }
}

private final class CueClip: @unchecked Sendable {
    var onFinished: (@Sendable () -> Void)?

    private var file: AudioFileID?
    private var audioQueue: AudioQueueRef?
    private var format = AudioStreamBasicDescription()
    private var didFinish = false

    func open(url: URL) -> Bool {
        var opened: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &opened) == noErr, let opened else {
            return false
        }
        file = opened

        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(opened, kAudioFilePropertyDataFormat, &formatSize, &format) == noErr else {
            return false
        }

        var byteCount: UInt64 = 0
        var propertySize = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(opened, kAudioFilePropertyAudioDataByteCount, &propertySize, &byteCount) == noErr,
              byteCount > 0, byteCount < 1_000_000 else {
            return false
        }

        var packetCount: UInt64 = 0
        propertySize = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(opened, kAudioFilePropertyAudioDataPacketCount, &propertySize, &packetCount) == noErr,
              packetCount > 0, packetCount < 10_000 else {
            return false
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        var created: AudioQueueRef?
        guard AudioQueueNewOutput(&format, cueBufferFinished, userData, nil, nil, 0, &created) == noErr,
              let created else {
            return false
        }
        audioQueue = created
        applyMagicCookie(from: opened, to: created)

        let packets = UInt32(packetCount)
        var maxPacket: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        AudioFileGetProperty(opened, kAudioFilePropertyMaximumPacketSize, &propertySize, &maxPacket)
        let capacity = max(UInt32(byteCount), maxPacket * packets)

        var buffer: AudioQueueBufferRef?
        guard AudioQueueAllocateBuffer(created, capacity, &buffer) == noErr, let buffer else {
            return false
        }

        var ioBytes = capacity
        var ioPackets = packets
        let variableRate = format.mBytesPerPacket == 0
        var descriptions = [AudioStreamPacketDescription](
            repeating: AudioStreamPacketDescription(),
            count: Int(packets)
        )
        let data = buffer.pointee.mAudioData
        let readStatus = descriptions.withUnsafeMutableBufferPointer { descBuf in
            AudioFileReadPacketData(
                opened,
                false,
                &ioBytes,
                variableRate ? descBuf.baseAddress : nil,
                0,
                &ioPackets,
                data
            )
        }
        guard readStatus == noErr, ioPackets > 0, ioBytes > 0 else { return false }
        buffer.pointee.mAudioDataByteSize = ioBytes

        let enqueueStatus = descriptions.withUnsafeBufferPointer { descBuf in
            AudioQueueEnqueueBuffer(
                created,
                buffer,
                variableRate ? ioPackets : 0,
                variableRate ? descBuf.baseAddress : nil
            )
        }
        guard enqueueStatus == noErr else { return false }
        AudioQueueSetParameter(created, kAudioQueueParam_Volume, 1)
        return true
    }

    func start() {
        guard let audioQueue else { return }
        AudioQueueStart(audioQueue, nil)
    }

    func bufferFinished() {
        guard !didFinish else { return }
        didFinish = true
        if let audioQueue {
            AudioQueueStop(audioQueue, false)
        }
        let notify = onFinished
        onFinished = nil
        notify?()
    }

    func shutdown() {
        didFinish = true
        onFinished = nil
        if let audioQueue {
            self.audioQueue = nil
            AudioQueueDispose(audioQueue, true)
        }
        if let file {
            self.file = nil
            AudioFileClose(file)
        }
    }

    deinit {
        shutdown()
    }

    private func applyMagicCookie(from file: AudioFileID, to queue: AudioQueueRef) {
        var cookieSize: UInt32 = 0
        var writable: UInt32 = 0
        guard AudioFileGetPropertyInfo(file, kAudioFilePropertyMagicCookieData, &cookieSize, &writable) == noErr,
              cookieSize > 0 else {
            return
        }
        var cookie = Data(count: Int(cookieSize))
        cookie.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var size = cookieSize
            guard AudioFileGetProperty(file, kAudioFilePropertyMagicCookieData, &size, base) == noErr else {
                return
            }
            AudioQueueSetProperty(queue, kAudioQueueProperty_MagicCookie, base, size)
        }
    }
}

private func cueBufferFinished(
    userData: UnsafeMutableRawPointer?,
    queue: AudioQueueRef,
    buffer: AudioQueueBufferRef
) {
    guard let userData else { return }
    Unmanaged<CueClip>.fromOpaque(userData).takeUnretainedValue().bufferFinished()
}
