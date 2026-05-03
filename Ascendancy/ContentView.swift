import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    
    @Query(
        filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" },
        sort: CompoundProtocol.listSortDescriptors
    )
    private var activeProtocols: [CompoundProtocol]

    @Query(sort: \DoseLog.timestamp, order: .reverse)
    private var allLogs: [DoseLog]
    
    @State private var selectedTab: Tab = .home
    
    enum Tab: String, CaseIterable {
        case home = "Home"
        case protocols = "Protocols"
        case logs = "Logs"
        case metrics = "Metrics"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .protocols: return "cross.vial.fill"
            case .logs: return "list.bullet.rectangle.fill"
            case .metrics: return "chart.xyaxis.line"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(Tab.home)
                .tabItem {
                    Label("Home", systemImage: Tab.home.icon)
                }
            
            ActiveProtocolsView()
                .tag(Tab.protocols)
                .tabItem {
                    Label("Protocols", systemImage: Tab.protocols.icon)
                }
            
            LogsView()
                .tag(Tab.logs)
                .tabItem {
                    Label("Logs", systemImage: Tab.logs.icon)
                }
            
            MetricsView()
                .tag(Tab.metrics)
                .tabItem {
                    Label("Metrics", systemImage: Tab.metrics.icon)
                }
        }
        .tint(.white)
        .onChange(of: widgetSnapshotFingerprint) { _, _ in
            WidgetSnapshotService.publish(protocols: activeProtocols, logs: allLogs)
        }
        .onChange(of: selectedTab) { _, _ in
            Haptics.selection()
        }
        .onAppear {
            setupTabBarAppearance()
            scheduleAllReminders()
        }
        .task {
            ProtocolSortMigration.normalizeIfNeeded(in: context)
            WidgetSnapshotService.publish(protocols: activeProtocols, logs: allLogs)
        }
    }

    private var widgetSnapshotFingerprint: String {
        let protocolPart = activeProtocols.map { protocol_ in
            [
                protocol_.id.uuidString,
                protocol_.name,
                protocol_.categoryRaw,
                protocol_.doseAmount.description,
                protocol_.doseUnitRaw,
                protocol_.scheduleData?.base64EncodedString() ?? "",
                protocol_.startDate.timeIntervalSince1970.description,
                protocol_.statusRaw,
                protocol_.inventoryCount.description,
                protocol_.inventoryLowThreshold.description,
                protocol_.inventoryUnitLabel,
                protocol_.remindersEnabled.description,
                protocol_.sortOrder.description
            ].joined(separator: ",")
        }.joined(separator: "|")
        let logPart = allLogs.prefix(200).map { log in
            [
                log.id.uuidString,
                log.protocol_?.id.uuidString ?? "",
                log.timestamp.timeIntervalSince1970.description,
                log.actualDoseAmount.description,
                log.doseUnitRaw
            ].joined(separator: ",")
        }.joined(separator: "|")
        return protocolPart + "::" + logPart
    }
    
    private func scheduleAllReminders() {
        Task {
            let auth = await NotificationService.shared.requestAuthorization()
            guard auth else { return }
            await NotificationService.shared.scheduleAll(protocols: activeProtocols)
        }
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.05, alpha: 1)
        
        let normalAttribs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(white: 0.5, alpha: 1)
        ]
        let selectedAttribs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white
        ]
        
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.4, alpha: 1)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttribs
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttribs
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
