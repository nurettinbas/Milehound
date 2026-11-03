import Foundation
import SwiftData
import AppIntents

@MainActor
enum VehiclePairingService {
    static func setDefaultVehicle(
        _ vehicle: VehicleProfile,
        in context: ModelContext,
        save: Bool = true
    ) {
        for item in fetchVehicles(in: context) {
            item.isDefault = item.id == vehicle.id
        }
        if save {
            try? context.save()
            if !UITestSupport.shouldSkipExternalEffects {
                MilehoundShortcuts.updateAppShortcutParameters()
            }
        }
    }

    @discardableResult
    static func deleteVehicle(
        _ vehicle: VehicleProfile,
        in context: ModelContext
    ) -> Bool {
        let wasDefault = vehicle.isDefault
        let photoFileName = vehicle.photoFileName
        let receiptFileNames = Set(vehicle.expenses.compactMap(\.receiptFileName))
        let vehicleID = vehicle.id
        VehicleCareNotificationScheduler.cancelAll(for: vehicleID)
        context.delete(vehicle)
        do {
            try context.save()
            if let photoFileName {
                VehiclePhotoStore.shared.remove(fileName: photoFileName)
            }
            for receipt in receiptFileNames {
                ExpenseReceiptStore.shared.removeIfUnreferenced(fileName: receipt, in: context)
            }
            if wasDefault, let next = fetchVehicles(in: context).first {
                setDefaultVehicle(next, in: context)
            } else if !UITestSupport.shouldSkipExternalEffects {
                MilehoundShortcuts.updateAppShortcutParameters()
            }
            VehicleCareNotificationScheduler.rescheduleAll(in: context)
            return true
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabDeleteFailed(error.localizedDescription))
            return false
        }
    }

    static func seedDefaultVehicleIfNeeded(in context: ModelContext) {
        let vehicles = fetchVehicles(in: context)
        guard vehicles.isEmpty else { return }

        let settings = AppSettings.shared
        let vehicle = VehicleProfile(
            name: L10n.vehicleDefaultName,
            consumption: settings.fuelLitersPer100km
        )
        context.insert(vehicle)
        setDefaultVehicle(vehicle, in: context)
    }

    /// Clears legacy in-app Bluetooth auto-start UserDefaults and vehicle route bindings.
    static func migrateLegacyBluetoothAutoStart(in context: ModelContext) {
        AppSettings.shared.migrateLegacyBluetoothAutoStartKeys()

        let vehicles = fetchVehicles(in: context)
        var didChange = false
        for vehicle in vehicles where vehicle.autoStartEnabled || vehicle.pairedRouteUID != nil {
            vehicle.autoStartEnabled = false
            vehicle.pairedRouteUID = nil
            vehicle.pairedRouteName = nil
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }

    private static func fetchVehicles(in context: ModelContext) -> [VehicleProfile] {
        (try? context.fetch(FetchDescriptor<VehicleProfile>())) ?? []
    }
}
