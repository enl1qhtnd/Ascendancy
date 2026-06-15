import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGoal") private var userGoal = ""
    @AppStorage("profileImageData") private var profileImageData: Data?
    
    @AppStorage("globalNotificationsEnabled") private var notificationsEnabled = true
    @State private var showReconCalc = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showProfileImageOptions = false
    @State private var showPhotoPicker = false
    @State private var showExpandedProfileImage = false
    @State private var showBackupExporter = false
    @State private var backupExportDocument: AscendancyBackupDocument?
    @State private var backupExportFilename = ""
    @State private var showBackupImporter = false
    @State private var pendingImportData: Data?
    @State private var showImportConfirmation = false
    @State private var backupAlert: BackupAlert?
    @State private var widgetSharedContainerAvailable = AppGroupSupport.isSharedContainerAvailable
    @State private var widgetAppGroupIdentifier = AppGroupSupport.appGroupIdentifier
    @State private var widgetSnapshotExists = AppGroupSupport.diagnostics().snapshotExists
    @State private var widgetSnapshotGeneratedAt = AppGroupSupport.diagnostics().snapshotGeneratedAt
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // Avatar / Name
                        VStack(spacing: 12) {
                            Button {
                                Haptics.tap()
                                showProfileImageOptions = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(AscendancyTheme.surfaceRaised)
                                        .frame(width: 96, height: 96)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                                        )
                                    
                                    if let data = profileImageData, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 86, height: 86)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 38, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                    
                                    // Small edit badge
                                    Circle()
                                        .fill(Color(white: 0.2))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                                        )
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white)
                                        )
                                        .offset(x: 32, y: 32)
                                }
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("", isPresented: $showProfileImageOptions, titleVisibility: .hidden) {
                                Button("Choose Photo") {
                                    showPhotoPicker = true
                                }

                                if profileImageData != nil {
                                    Button("Expand Photo") {
                                        showExpandedProfileImage = true
                                    }

                                    Button("Remove Photo", role: .destructive) {
                                        profileImageData = nil
                                        selectedPhotoItem = nil
                                    }
                                }
                            }
                            .photosPicker(
                                isPresented: $showPhotoPicker,
                                selection: $selectedPhotoItem,
                                matching: .images
                            )
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                Task { @MainActor in
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data),
                                       let compressed = uiImage.jpegData(compressionQuality: 0.8) {
                                        profileImageData = compressed
                                        Haptics.success()
                                    }
                                }
                            }

                            if !userName.isEmpty {
                                Text(userName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        
                        // Profile
                        settingsSection("Profile") {
                            VStack(spacing: 12) {
                                settingsField(label: "Name", placeholder: "Your name", text: $userName)
                                AscendancyDivider()
                                settingsField(label: "Goal", placeholder: "e.g. Optimize performance", text: $userGoal)
                            }
                        }
                        
                        // Notifications
                        settingsSection("Notifications") {
                            settingsToggleRow(title: "Dose Reminders", isOn: $notificationsEnabled)
                        }
                        
                        // Tools
                        settingsSection("Tools") {
                            Button {
                                Haptics.tap()
                                showReconCalc = true
                            } label: {
                                HStack {
                                    Label("Reconstitution Calculator", systemImage: "flask.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        }

                        // Backup
                        settingsSection("Backup") {
                            settingsActionRow(title: "Export Backup", systemImage: "square.and.arrow.up") {
                                exportBackup()
                            }
                            AscendancyDivider()
                            settingsActionRow(
                                title: "Import Backup",
                                systemImage: "square.and.arrow.down",
                                longPressMinimumDuration: 5,
                                longPressAction: pasteBackupFromClipboard
                            ) {
                                Haptics.tap()
                                showBackupImporter = true
                            }
                            AscendancyDivider()
                            iCloudSyncRow
                        }

                        // Widget
                        settingsSection("Widget") {
                            widgetSharedContainerRow
                        }
                        
                        // App info
                        settingsSection("About") {
                            VStack(spacing: 10) {
                                infoRow(label: "Version", value: Bundle.main.appVersion)
                                AscendancyDivider()
                                infoRow(label: "Build", value: Bundle.main.buildNumber)
                            }
                        }
                        
                        Text("made with ❤️ by @enl1qhtnd")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.25))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Preferences")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showReconCalc) {
                ReconstitutionCalculatorView()
            }
            .fullScreenCover(isPresented: $showExpandedProfileImage) {
                expandedProfileImageView
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupExportDocument,
                contentType: .ascendancyBackup,
                defaultFilename: backupExportFilename
            ) { result in
                backupExportDocument = nil
                switch result {
                case .success:
                    Haptics.success()
                    backupAlert = BackupAlert(title: String(localized: "Backup Exported"), message: String(localized: "Your backup file was created."))
                case .failure(let error):
                    Haptics.error()
                    backupAlert = BackupAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.ascendancyBackup, .json],
                allowsMultipleSelection: false
            ) { result in
                readBackupImportResult(result)
            }
            .alert("Import Backup?", isPresented: $showImportConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingImportData = nil
                }
                Button("Replace Data", role: .destructive) {
                    restorePendingBackup()
                }
            } message: {
                Text("This replaces protocols, logs, files, and profile settings. iCloud Sync may apply these changes on your other devices.")
            }
            .alert(item: $backupAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                refreshWidgetContainerStatus()
            }
            .onChange(of: notificationsEnabled) { _, newValue in
                Task {
                    if newValue {
                        await NotificationService.shared.scheduleAll(protocols: fetchActiveProtocols())
                    } else {
                        await NotificationService.shared.cancelAllRemindersAsync()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedProfileImageView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = profileImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.tap()
                        showExpandedProfileImage = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AscendancyTheme.surfaceRaised)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }

    private func refreshWidgetContainerStatus() {
        let diagnostics = AppGroupSupport.diagnostics()
        widgetSharedContainerAvailable = diagnostics.isSharedContainerAvailable
        widgetAppGroupIdentifier = diagnostics.identifier
        widgetSnapshotExists = diagnostics.snapshotExists
        widgetSnapshotGeneratedAt = diagnostics.snapshotGeneratedAt

        if diagnostics.isSharedContainerAvailable && !diagnostics.snapshotExists {
            WidgetSnapshotService.publish(from: context)
            let refreshed = AppGroupSupport.diagnostics()
            widgetSnapshotExists = refreshed.snapshotExists
            widgetSnapshotGeneratedAt = refreshed.snapshotGeneratedAt
        }
    }

    private func fetchActiveProtocols() -> [CompoundProtocol] {
        let descriptor = FetchDescriptor<CompoundProtocol>(
            predicate: #Predicate { $0.statusRaw == "Active" },
            sortBy: CompoundProtocol.listSortDescriptors
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(catalogKey: title)
                .ascendancyCardHeading()
            VStack(spacing: 12) {
                content()
            }
            .glassCard()
        }
    }
    
    private func settingsField(label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(catalogKey: label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(catalogKey: label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func settingsActionRow(
        title: String,
        systemImage: String,
        longPressMinimumDuration: TimeInterval? = nil,
        longPressAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if let longPressMinimumDuration, let longPressAction {
            settingsActionLabel(title: title, systemImage: systemImage)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: longPressMinimumDuration)
                        .onEnded { _ in longPressAction() }
                        .exclusively(before: TapGesture().onEnded { action() })
                )
        } else {
            Button(action: action) {
                settingsActionLabel(title: title, systemImage: systemImage)
            }
        }
    }

    private func settingsActionLabel(title: String, systemImage: String) -> some View {
        HStack {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(catalogKey: title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
        }
    }

    private var widgetSharedContainerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Shared Widget Container", systemImage: "square.stack.3d.up.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(widgetSharedContainerAvailable ? 0.8 : 0.35))

                    if !widgetSharedContainerAvailable {
                        Text(widgetSharedContainerHelpText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }

                Spacer()

                Text(catalogKey: widgetSharedContainerAvailable ? "Available" : "Unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(widgetSharedContainerAvailable ? .green.opacity(0.85) : .white.opacity(0.3))
            }

            Text(widgetAppGroupIdentifier)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.22))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if widgetSharedContainerAvailable {
                Text(widgetSnapshotStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(widgetSnapshotExists ? .green.opacity(0.7) : .orange.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var widgetSnapshotStatusText: String {
        if let widgetSnapshotGeneratedAt {
            String(
                format: String(localized: "Widget snapshot updated %@"),
                widgetSnapshotGeneratedAt.formatted(date: .omitted, time: .shortened)
            )
        } else {
            String(localized: "Widget snapshot not published yet")
        }
    }

    private var widgetSharedContainerHelpText: String {
        if AppDistribution.isSideloaded {
            String(localized: "Sign the app and widget extension with the same App Group entitlement")
        } else {
            String(localized: "App Group container is not accessible")
        }
    }

    private var iCloudSyncRow: some View {
        let supportsCloudKitSync = AppDistribution.supportsCloudKitSync

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Label("iCloud Sync", systemImage: "icloud.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(supportsCloudKitSync ? 0.8 : 0.35))

                if !supportsCloudKitSync {
                    Text("Unavailable in sideloaded builds")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            Spacer()

            Text(catalogKey: supportsCloudKitSync ? "Enabled" : "Disabled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(supportsCloudKitSync ? .green.opacity(0.85) : .white.opacity(0.3))
        }
        .accessibilityElement(children: .combine)
    }

    private func exportBackup() {
        Haptics.tap()
        do {
            let data = try BackupService.exportData(from: context)
            backupExportDocument = AscendancyBackupDocument(data: data)
            backupExportFilename = BackupService.defaultFileName()
            showBackupExporter = true
            } catch {
                Haptics.error()
                backupAlert = BackupAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
    }

    private func pasteBackupFromClipboard() {
        let pasteboard = UIPasteboard.general
        let pastedString: String? = {
            if let string = pasteboard.string {
                return string
            }
            let jsonType = UTType.json.identifier
            let plainTextType = UTType.plainText.identifier
            if let data = pasteboard.data(forPasteboardType: jsonType) ?? pasteboard.data(forPasteboardType: plainTextType) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }()

        guard let pastedString else {
            Haptics.error()
            backupAlert = BackupAlert(
                title: String(localized: "Import Failed"),
                message: String(localized: "Clipboard does not contain backup data.")
            )
            return
        }

        do {
            pendingImportData = try BackupService.dataFromPastedString(pastedString)
            Haptics.warning()
            showImportConfirmation = true
        } catch {
            Haptics.error()
            backupAlert = BackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    private func readBackupImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                pendingImportData = try BackupService.dataFromImportedFile(at: url)
                Haptics.warning()
                showImportConfirmation = true
            } catch {
                Haptics.error()
                backupAlert = BackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
            }
        case .failure(let error):
            Haptics.error()
            backupAlert = BackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    private func restorePendingBackup() {
        guard let pendingImportData else { return }
        do {
            let summary = try BackupService.restore(from: pendingImportData, into: context)
            self.pendingImportData = nil
            Haptics.success()
            backupAlert = BackupAlert(title: String(localized: "Backup Imported"), message: summary.message)
        } catch {
            self.pendingImportData = nil
            Haptics.error()
            backupAlert = BackupAlert(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }
}

private struct BackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension Bundle {
    /// Marketing version from Info.plist (`$(MARKETING_VERSION)`), e.g. "1.8".
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number from Info.plist (`$(CURRENT_PROJECT_VERSION)`), e.g. "10".
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    ProfileSettingsView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self, MediaDocument.self], inMemory: true)
}
