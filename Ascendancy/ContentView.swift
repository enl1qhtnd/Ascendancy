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
    
    @State private var selectedTab: AppTab = .home
    @State private var showLogDosePicker = false
    @State private var lastPrimaryTab: AppTab = .home
    @State private var pendingOpenedBackupData: Data?
    @State private var showOpenedBackupConfirmation = false
    @State private var openedBackupAlert: OpenedBackupAlert?
    
    enum AppTab: Hashable {
        case home
        case protocols
        case logs
        case metrics
        case logDose
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .protocols: return "cross.vial.fill"
            case .logs: return "list.bullet.rectangle.fill"
            case .metrics: return "chart.xyaxis.line"
            case .logDose: return "plus"
            }
        }
        
        var title: String {
            switch self {
            case .home: return "Home"
            case .protocols: return "Protocols"
            case .logs: return "Logs"
            case .metrics: return "Metrics"
            case .logDose: return "Log Dose"
            }
        }
    }
    
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .tint(.white)
        .sheet(isPresented: $showLogDosePicker) {
            LogDoseFlowSheet(
                doses: DoseScheduleDayHelper.scheduledRows(protocols: activeProtocols, on: Date()),
                logs: allLogs
            )
        }
        .alert("Import Backup?", isPresented: $showOpenedBackupConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingOpenedBackupData = nil
            }
            Button("Replace Data", role: .destructive) {
                restoreOpenedBackup()
            }
        } message: {
            Text("This replaces protocols, logs, files, and profile settings. iCloud Sync may apply these changes on your other devices.")
        }
        .alert(item: $openedBackupAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onOpenURL { url in
            readOpenedBackup(from: url)
        }
        .onChange(of: widgetSnapshotFingerprint) { _, _ in
            WidgetSnapshotService.publish(protocols: activeProtocols, logs: allLogs)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .logDose {
                Haptics.tap()
                showLogDosePicker = true
                selectedTab = oldValue == .logDose ? lastPrimaryTab : oldValue
            } else if oldValue != .logDose {
                lastPrimaryTab = newValue
                Haptics.selection()
            } else {
                lastPrimaryTab = newValue
            }
        }
        .onAppear {
            setupTabBarAppearance()
            scheduleAllReminders()
            WidgetSnapshotService.publish(protocols: activeProtocols, logs: allLogs)
        }
        .task {
            ProtocolSortMigration.normalizeIfNeeded(in: context)
            WidgetSnapshotService.publish(protocols: activeProtocols, logs: allLogs)
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.icon, value: AppTab.home) {
                HomeView()
            }
            
            Tab(AppTab.protocols.title, systemImage: AppTab.protocols.icon, value: AppTab.protocols) {
                ActiveProtocolsView()
            }
            
            Tab(AppTab.logs.title, systemImage: AppTab.logs.icon, value: AppTab.logs) {
                LogsView()
            }
            
            Tab(AppTab.metrics.title, systemImage: AppTab.metrics.icon, value: AppTab.metrics) {
                MetricsView()
            }
            
            Tab(value: AppTab.logDose, role: .search) {
                Color.clear
            } label: {
                Image(systemName: "plus")
            }
        }
    }
    
    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(AppTab.home)
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.icon)
                }
            
            ActiveProtocolsView()
                .tag(AppTab.protocols)
                .tabItem {
                    Label(AppTab.protocols.title, systemImage: AppTab.protocols.icon)
                }
            
            LogsView()
                .tag(AppTab.logs)
                .tabItem {
                    Label(AppTab.logs.title, systemImage: AppTab.logs.icon)
                }
            
            MetricsView()
                .tag(AppTab.metrics)
                .tabItem {
                    Label(AppTab.metrics.title, systemImage: AppTab.metrics.icon)
                }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.tap()
                showLogDosePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 20)
            .padding(.bottom, 56)
            .accessibilityLabel("Log Dose")
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
            guard NotificationService.globalNotificationsEnabled else { return }
            let auth = await NotificationService.shared.requestAuthorization()
            guard auth else { return }
            await NotificationService.shared.scheduleAll(protocols: activeProtocols)
        }
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.08)

        let normalAttribs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(white: 0.5, alpha: 1)
        ]
        let selectedAttribs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white
        ]

        let itemAppearances = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for itemAppearance in itemAppearances {
            itemAppearance.normal.iconColor = UIColor(white: 0.4, alpha: 1)
            itemAppearance.selected.iconColor = UIColor.white
            itemAppearance.normal.titleTextAttributes = normalAttribs
            itemAppearance.selected.titleTextAttributes = selectedAttribs
        }

        let tabBar = UITabBar.appearance()
        tabBar.isTranslucent = true
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func readOpenedBackup(from url: URL) {
        do {
            pendingOpenedBackupData = try BackupService.dataFromImportedFile(at: url)
            Haptics.warning()
            showOpenedBackupConfirmation = true
        } catch {
            pendingOpenedBackupData = nil
            Haptics.error()
            openedBackupAlert = OpenedBackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    private func restoreOpenedBackup() {
        guard let pendingOpenedBackupData else { return }

        do {
            let summary = try BackupService.restore(from: pendingOpenedBackupData, into: context)
            self.pendingOpenedBackupData = nil
            WidgetSnapshotService.publish(from: context)
            Haptics.success()
            openedBackupAlert = OpenedBackupAlert(title: String(localized: "Backup Imported"), message: summary.message)
        } catch {
            self.pendingOpenedBackupData = nil
            Haptics.error()
            openedBackupAlert = OpenedBackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }
}

private struct OpenedBackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
