import Foundation
import SwiftData

enum MilehoundSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self, TravelJournal.self]
    }
}

/// Legacy in-memory / test schema before connection fields on vehicles.
/// Care models are listed because live `VehicleProfile` relationships require them in the same schema.
enum MilehoundSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
    }
}

enum MilehoundSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
    }
}

/// Adds precomputed derived fields on `Trip` (night distance, start/end coordinates, search index).
/// All are optional and additive, so existing rows open with `nil` and are backfilled at runtime by
/// `TripDerivedBackfillService`. No property is removed or renamed.
enum MilehoundSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
    }
}

/// Adds the `TripDailyRollup` aggregate table. Purely additive: a brand new entity, no change to
/// any existing one, so nothing a user recorded is touched. The table is derived data and is
/// populated by `TripRollupService.rebuildAll` on first launch after the upgrade.
enum MilehoundSchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional `VehicleProfile.photoFileName` (disk thumb path key). Additive only.
enum MilehoundSchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds vehicle care schedules/expenses and optional `currentOdometerKm`. Purely additive.
enum MilehoundSchemaV13: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional installment fields on `VehicleExpense` (`installmentGroupID`, index, count, total).
/// Additive only: existing one-shot rows stay `nil` and keep their amount/date.
enum MilehoundSchemaV14: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds cruise / stop derived fields on `Trip` and matching totals on `TripDailyRollup`.
/// All additive: existing trips open with `nil` cruise/stop and are backfilled at runtime;
/// rollup columns default to 0 until `TripRollupService` rebuilds.
enum MilehoundSchemaV15: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(15, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional per-trip fuel estimate inputs on `Trip` (`fuelConsumptionPer100`, `fuelUnitPrice`).
/// Additive only: existing rows open with `nil` and keep their stored `estimatedFuelCost`.
enum MilehoundSchemaV16: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional `Trip.mostCommonSpeedKmh` and matching weight/product totals on
/// `TripDailyRollup`. Additive only: existing trips open with `nil` and are backfilled;
/// rollup columns default to 0 until `TripRollupService` rebuilds.
enum MilehoundSchemaV17: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(17, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional `Trip.dynamicFuelCost` and matching total on `TripDailyRollup`.
/// Additive only: existing trips open with `nil` and are backfilled; rollup column defaults
/// to 0 until `TripRollupService` rebuilds. Does not rewrite `estimatedFuelCost` (avg fuel).
enum MilehoundSchemaV18: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(18, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds `TravelJournal` and optional `Trip.journalID`. Additive only: existing trips open
/// unassigned (`journalID == nil`).
enum MilehoundSchemaV19: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(19, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional smart-category fields on `Trip` (`pendingSuggestedCategoryID`,
/// `pendingSuggestionReasonRaw`, `categoryOriginRaw`). Additive only: existing rows open
/// with `nil` and keep their stored `categoryRaw`.
enum MilehoundSchemaV20: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(20, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional locality / country fields on `Trip` plus derived `FrequentRouteAggregate`,
/// `AchievementProgress`, and `VisitedLocality` tables. Additive only.
enum MilehoundSchemaV21: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(21, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional GPS-fuel volume / measurement fields on `Trip`, volume totals on
/// `TripDailyRollup`, and `VehicleFuelCalibration`. Additive only: existing trips open with
/// `nil` fuel extras and keep `estimatedFuelCost` / GPS traces. Runtime still opens a single
/// live schema (same as V21) so VersionedSchema checksums do not collide; SwiftData lightweight
/// migration adds the optional columns and new table.
enum MilehoundSchemaV22: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(22, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional `VehicleExpense.receiptFileName` (receipt photo on disk, never image bytes in the
/// store). Additive only: existing expenses open with `nil` and keep amounts, dates, and
/// installments. Runtime opens the single live schema; lightweight migration adds the column.
enum MilehoundSchemaV23: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(23, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Adds optional odometer anchor fields on `VehicleProfile` (`odometerAnchorKm`, `odometerAnchorAt`,
/// `odometerTripMetersSinceAnchor`). Additive only: existing vehicles open with `nil` and keep
/// `currentOdometerKm`. `VehicleOdometerService.backfillAnchorsIfNeeded` copies that reading once
/// so older trips are not added again.
enum MilehoundSchemaV24: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(24, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

/// Schema history used by in-memory migration tests.
/// Do not pass `MilehoundMigrationPlan` to a runtime disk `ModelContainer` — SwiftData aborts with
/// "Duplicate version checksums detected" when multiple enums reference the same live `@Model` types.
/// Tip schema must be a single live-model enum (V24); V11–V23 stay for older in-memory test containers.
enum MilehoundMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MilehoundSchemaV5.self, MilehoundSchemaV24.self]
    }

    static var stages: [MigrationStage] {
        [migrateV5toV24]
    }

    static let migrateV5toV24 = MigrationStage.lightweight(
        fromVersion: MilehoundSchemaV5.self,
        toVersion: MilehoundSchemaV24.self
    )
}
