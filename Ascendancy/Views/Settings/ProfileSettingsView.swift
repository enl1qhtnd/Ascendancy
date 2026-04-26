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
    
    @State private var notificationsEnabled = true
    @State private var showReconCalc = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showBackupExporter = false
    @State private var backupExportDocument: AscendancyBackupDocument?
    @State private var backupExportFilename = ""
    @State private var showBackupImporter = false
    @State private var pendingImportData: Data?
    @State private var showImportConfirmation = false
    @State private var backupAlert: BackupAlert?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // Avatar / Name
                        VStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 72, height: 72)
                                    
                                    if let data = profileImageData, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 32))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    
                                    // Small edit badge
                                    Circle()
                                        .fill(Color(white: 0.2))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white)
                                        )
                                        .offset(x: 24, y: 24)
                                }
                            }
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
                            
                            if profileImageData != nil {
                                Button("Remove Photo", role: .destructive) {
                                    profileImageData = nil
                                    selectedPhotoItem = nil
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.8))
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
                            Toggle("Dose Reminders", isOn: $notificationsEnabled)
                                .foregroundStyle(.white)
                                .tint(.green)
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
                            settingsActionRow(title: "Import Backup", systemImage: "square.and.arrow.down") {
                                Haptics.tap()
                                showBackupImporter = true
                            }
                            AscendancyDivider()
                            iCloudSyncRow
                        }
                        
                        // App info
                        settingsSection("About") {
                            VStack(spacing: 10) {
                                infoRow(label: "Version", value: "1.4")
                                AscendancyDivider()
                                infoRow(label: "Build", value: "5")
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
                    Text("Profile & Settings")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
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
                    backupAlert = BackupAlert(title: "Backup Exported", message: "Your backup file was created.")
                case .failure(let error):
                    Haptics.error()
                    backupAlert = BackupAlert(title: "Export Failed", message: error.localizedDescription)
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
        }
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(catalogKey: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.8)
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

    private func settingsActionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private var iCloudSyncRow: some View {
        let supportsCloudKitSync = AppDistribution.supportsCloudKitSync

        HStack {
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

            Text(supportsCloudKitSync ? "Enabled" : "Disabled")
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
            backupAlert = BackupAlert(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func readBackupImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                pendingImportData = try Data(contentsOf: url)
                Haptics.warning()
                showImportConfirmation = true
            } catch {
                Haptics.error()
                backupAlert = BackupAlert(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            Haptics.error()
            backupAlert = BackupAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func restorePendingBackup() {
        guard let pendingImportData else { return }
        do {
            let summary = try BackupService.restore(from: pendingImportData, into: context)
            self.pendingImportData = nil
            Haptics.success()
            backupAlert = BackupAlert(title: "Backup Imported", message: summary.message)
        } catch {
            self.pendingImportData = nil
            Haptics.error()
            backupAlert = BackupAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

private struct BackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    ProfileSettingsView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self, MediaDocument.self], inMemory: true)
}
