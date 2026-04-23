import SwiftUI
import PhotosUI

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGoal") private var userGoal = ""
    @AppStorage("profileImageData") private var profileImageData: Data?
    
    @State private var notificationsEnabled = true
    @State private var showReconCalc = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showBackupExport = false
    @State private var showBackupImport = false
    
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
                        
                        // Export Backup
                        settingsSection("Export Backup") {
                            Button {
                                Haptics.tap()
                                showBackupExport = true
                            } label: {
                                HStack {
                                    Label("Export Backup", systemImage: "arrow.down.doc")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        }

                        // Import Backup
                        settingsSection("Import Backup") {
                            Button {
                                Haptics.tap()
                                showBackupImport = true
                            } label: {
                                HStack {
                                    Label("Import Backup", systemImage: "arrow.up.doc")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
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
            .sheet(isPresented: $showBackupExport) {
                BackupExportView()
            }
            .sheet(isPresented: $showBackupImport) {
                BackupImportView()
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
}

#Preview {
    ProfileSettingsView()
        .preferredColorScheme(.dark)
}
