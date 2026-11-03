import Foundation
import SwiftData

@Model
final class VehicleSchedule {
    var id: UUID
    var kindRaw: String
    var title: String
    var isEnabled: Bool
    var nextDueDate: Date?
    var nextDueOdometerKm: Int?
    var intervalKindRaw: String
    var intervalMonths: Int?
    var intervalKm: Int?
    var lastCompletedAt: Date?
    var lastCompletedOdometerKm: Int?
    /// Comma-separated day offsets, e.g. "30,7,1".
    var reminderOffsetsDaysRaw: String
    var notes: String?

    var vehicle: VehicleProfile?

    init(
        id: UUID = UUID(),
        kind: VehicleScheduleKind,
        title: String? = nil,
        isEnabled: Bool = true,
        nextDueDate: Date? = nil,
        nextDueOdometerKm: Int? = nil,
        intervalKind: VehicleScheduleIntervalKind = .none,
        intervalMonths: Int? = nil,
        intervalKm: Int? = nil,
        lastCompletedAt: Date? = nil,
        lastCompletedOdometerKm: Int? = nil,
        reminderOffsetsDays: [Int]? = nil,
        notes: String? = nil,
        vehicle: VehicleProfile? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title ?? kind.defaultTitle
        self.isEnabled = isEnabled
        self.nextDueDate = nextDueDate
        self.nextDueOdometerKm = nextDueOdometerKm
        self.intervalKindRaw = intervalKind.rawValue
        self.intervalMonths = intervalMonths
        self.intervalKm = intervalKm
        self.lastCompletedAt = lastCompletedAt
        self.lastCompletedOdometerKm = lastCompletedOdometerKm
        let offsets = reminderOffsetsDays ?? kind.defaultReminderOffsets
        self.reminderOffsetsDaysRaw = Self.encodeOffsets(offsets)
        self.notes = notes
        self.vehicle = vehicle
    }

    var kind: VehicleScheduleKind {
        get { VehicleScheduleKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var intervalKind: VehicleScheduleIntervalKind {
        get { VehicleScheduleIntervalKind(rawValue: intervalKindRaw) ?? .none }
        set { intervalKindRaw = newValue.rawValue }
    }

    var reminderOffsetsDays: [Int] {
        get { Self.decodeOffsets(reminderOffsetsDaysRaw) }
        set { reminderOffsetsDaysRaw = Self.encodeOffsets(newValue) }
    }

    static func encodeOffsets(_ offsets: [Int]) -> String {
        offsets.sorted(by: >).map(String.init).joined(separator: ",")
    }

    static func decodeOffsets(_ raw: String) -> [Int] {
        raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
            .sorted(by: >)
    }
}
