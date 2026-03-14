import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(filter: #Predicate<CompoundProtocol> { $0.statusRaw == "Active" })
    private var activeProtocols: [CompoundProtocol]
    
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
        .onAppear {
            setupTabBarAppearance()
            scheduleAllReminders()
        }
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
