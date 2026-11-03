import Foundation
import UIKit

/// Full-resolution vehicle mark for Live Activity / Dynamic Island.
/// Bytes live in the App Group container; ActivityKit `ContentState` only carries a revision token
/// so the ~4 KB payload budget is never spent on JPEG/PNG.
enum LiveActivityVehicleMarkStore {
    private static let fileName = "live-activity-vehicle-mark.png"

    /// Override for unit tests — never set in production.
    @MainActor static var directoryOverride: URL?

    @MainActor private static var cachedRevision: String?
    @MainActor private static var cachedImage: UIImage?

    /// Atomically writes a PNG mark. Returns a revision token for `ContentState`.
    @MainActor
    static func write(_ image: UIImage) -> String? {
        guard let data = image.pngData(), !data.isEmpty else { return nil }
        guard let directory = containerDirectory() else {
            DevLog.shared.log(.widget, "Live Activity mark: App Group container missing", level: .warning)
            return nil
        }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let destination = directory.appendingPathComponent(fileName)
        let temp = directory.appendingPathComponent("\(fileName).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temp, to: destination)
        } catch {
            try? fileManager.removeItem(at: temp)
            DevLog.shared.log(
                .widget,
                "Live Activity mark: write failed (\(error.localizedDescription))",
                level: .warning
            )
            return nil
        }
        let revision = UUID().uuidString
        let decoded = UIImage(data: data) ?? image
        cachedRevision = revision
        cachedImage = decoded
        DevLog.shared.log(.widget, "Live Activity mark: App Group photo written (\(data.count) B)")
        return revision
    }

    /// Memory hit when `revision` matches the last write; otherwise loads from disk once.
    @MainActor
    static func image(revision: String?) -> UIImage? {
        guard let revision, !revision.isEmpty else { return nil }
        if revision == cachedRevision, let cachedImage {
            return cachedImage
        }
        guard let directory = containerDirectory() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        cachedRevision = revision
        cachedImage = image
        return image
    }

    @MainActor
    static func clear() {
        cachedRevision = nil
        cachedImage = nil
        guard let directory = containerDirectory() else { return }
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    private static func containerDirectory() -> URL? {
        if let directoryOverride { return directoryOverride }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: RecordingControlBridge.appGroupSuiteName
        )
    }
}
