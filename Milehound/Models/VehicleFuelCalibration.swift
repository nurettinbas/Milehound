import Foundation
import SwiftData

/// Per-vehicle bias learned from user-measured trip L/100 values.
@Model
final class VehicleFuelCalibration {
    var vehicleID: UUID
    var bias: Double
    var biasLog: Double
    var acceptedCount: Int
    var wape: Double
    var maeRate: Double
    var confidence: Double
    var speedWeight: Double
    var idleWeight: Double
    var transientWeight: Double
    var coldWeight: Double
    var updatedAt: Date

    init(vehicleID: UUID) {
        self.vehicleID = vehicleID
        self.bias = 1
        self.biasLog = 0
        self.acceptedCount = 0
        self.wape = 0
        self.maeRate = 0
        self.confidence = 0
        self.speedWeight = 1
        self.idleWeight = 1
        self.transientWeight = 1
        self.coldWeight = 1
        self.updatedAt = Date()
    }

    var snapshot: FuelCalibrationSnapshot {
        FuelCalibrationSnapshot(
            bias: bias,
            speedWeight: speedWeight,
            idleWeight: idleWeight,
            transientWeight: transientWeight,
            coldWeight: coldWeight,
            acceptedCount: acceptedCount,
            confidence: confidence
        )
    }
}
