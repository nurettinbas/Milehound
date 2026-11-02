import Foundation
import SwiftData

enum ModelContainerFactory {
    private static let storeFileName = "Trailhound.store"
    private static let schemaVersionKey = "trailhound.swiftdata.schemaVersion"
    private static let recoveryNoticeKey = "store.recovery.notice.shown"
    private static let minimumBackupBytesForNotice: Int64 = 8_192
    static let currentSchemaVersion = 24

    static var storeURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(storeFileName)
    }

    private static var liveSchema: Schema {
        Schema([
            Trip.self,
            TripPoint.self,
            SavedPlace.self,
            TripStop.self,
            UserCategory.self,
            MatchedRoutePoint.self,
            VehicleProfile.self,
            TripDailyRollup.self,
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
            FrequentRouteAggregate.self,
            AchievementProgress.self,
            VisitedLocality.self,
            VehicleFuelCalibration.self,
        ])
    }

    private static func applyFileProtectionIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    static func makeSafe() -> ModelContainer {
        if let container = openPersistedStore() {
            return container
        }

        #if DEBUG
        print("SwiftData: primary open failed, retrying after sidecar cleanup")
        #endif
        deleteStoreSidecars()
        if let container = openPersistedStore() {
            return container
        }

        switch resetStoreWithBackup() {
        case .success(let result):
            markSchemaCurrent()
            applyFileProtectionIfNeeded(at: storeURL)
            notifyRecoveryIfNeeded(backupBytes: result.backupBytes)
            return result.container
        case .failure:
            break
        }

        #if DEBUG
        print("SwiftData: disk store unavailable, using in-memory fallback")
        #endif
        Task { @MainActor in
            AppErrorPresenter.shared.present(L10n.storeOpenFailedInMemory)
        }
        if let container = try? makeInMemory() {
            return container
        }
        return emergencyContainer()
    }

    private static func openPersistedStore() -> ModelContainer? {
        do {
            let container = try makePersistedContainer()
            markSchemaCurrent()
            applyFileProtectionIfNeeded(at: storeURL)
            return container
        } catch {
            #if DEBUG
            print("SwiftData: open failed: \(error)")
            #endif
            return nil
        }
    }

    static func makePersistedContainer() throws -> ModelContainer {
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: liveSchema, configurations: config)
    }

    static func makeInMemory() throws -> ModelContainer {
        // A fresh name so a second in-memory container does not reset models the previous
        // test still holds. The on-disk store is untouched.
        let name = "memory-\(UUID().uuidString)"
        let config = ModelConfiguration(name, schema: liveSchema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: liveSchema, configurations: config)
    }

    private struct ResetResult {
        let container: ModelContainer
        let backupBytes: Int64
    }

    private static func markSchemaCurrent() {
        UserDefaults.standard.set(currentSchemaVersion, forKey: schemaVersionKey)
    }

    private static func deleteStoreSidecars() {
        let base = storeURL
        for url in [
            URL(fileURLWithPath: base.path + "-shm"),
            URL(fileURLWithPath: base.path + "-wal")
        ] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func resetStoreWithBackup() -> Result<ResetResult, Error> {
        let base = storeURL
        var backupBytes: Int64 = 0
        if FileManager.default.fileExists(atPath: base.path) {
            backupBytes = fileSize(at: base)
            let backup = base
                .deletingLastPathComponent()
                .appendingPathComponent("Trailhound.store.backup-\(Int(Date().timeIntervalSince1970))")
            do {
                try FileManager.default.moveItem(at: base, to: backup)
            } catch {
                try? FileManager.default.removeItem(at: base)
            }
            deleteStoreSidecars()
        }
        do {
            let container = try makePersistedContainer()
            return .success(ResetResult(container: container, backupBytes: backupBytes))
        } catch {
            return .failure(error)
        }
    }

    private static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private static func notifyRecoveryIfNeeded(backupBytes: Int64) {
        guard backupBytes >= minimumBackupBytesForNotice else { return }
        guard !UserDefaults.standard.bool(forKey: recoveryNoticeKey) else { return }
        UserDefaults.standard.set(true, forKey: recoveryNoticeKey)
        Task { @MainActor in
            AppErrorPresenter.shared.presentInfo(L10n.storeRecoveredAfterReset)
        }
    }

    private static func emergencyContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: liveSchema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: liveSchema, configurations: config)
    }
}
