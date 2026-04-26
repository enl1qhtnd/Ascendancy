import SwiftUI
import SwiftData

@main
struct AscendancyApp: App {
    
    var sharedModelContainer: ModelContainer = {
        let isRunningTests = AppDistribution.isRunningTests
        let supportsCloudKitSync = AppDistribution.supportsCloudKitSync
        let schema = Schema([
            CompoundProtocol.self,
            DoseLog.self,
            MediaDocument.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningTests,
            cloudKitDatabase: supportsCloudKitSync ? .private("iCloud.de.enl1qhtnd.asce") : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
