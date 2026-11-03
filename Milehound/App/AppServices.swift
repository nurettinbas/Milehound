import SwiftData
import SwiftUI

/// Shared application services accessible from AppDelegate and SwiftUI.
@MainActor
enum AppServices {
    static let modelContainer: ModelContainer = {
        let container: ModelContainer
        if UITestSupport.isEnabled, let inMemory = try? ModelContainerFactory.makeInMemory() {
            // Each XCUITest launch gets a clean library so leftover simulator trips cannot
            // steal `trips.row.first` from the smart-category commute fixture.
            container = inMemory
        } else {
            container = ModelContainerFactory.makeSafe()
        }
        UITestSupport.configureAppIfNeeded()
        UITestSupport.seedSampleTripIfNeeded(container: container)
        return container
    }()
    static let runtime = AppRuntime()

    static func bootstrapRecordingIfNeeded() {
        runtime.bootstrapRecording(container: modelContainer)
    }
}
