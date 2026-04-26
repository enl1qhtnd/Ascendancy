import SwiftUI
import SwiftData

@main
struct AscendancyApp: App {
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CompoundProtocol.self,
            DoseLog.self,
            MediaDocument.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.de.enl1qhtnd.asce")
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
