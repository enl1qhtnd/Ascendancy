import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGoal") private var userGoal = ""
    @AppStorage("profileImageData") private var profileImageData: Data?

    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var backupMetadata: BackupMetadata?
    @State private var mergeStrategy: MergeStrategy = .replaceAll
    @State private var errorMessage: String?
    @State private var importSuccess = false
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Icon
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 32)

                        // Title
                        VStack(spacing: 8) {
                            Text("Import Backup")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Restore your data from a backup file")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }

                        if isImporting {
                            // Progress indicator
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.white)

                                Text("Restoring backup...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))

                                Text("This may take a few moments")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.vertical, 40)
                        } else if let error = errorMessage {
                            // Error state
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.red.opacity(0.8))

                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)

                                Button("Try Again") {
                                    Haptics.tap()
                                    errorMessage = nil
                                    selectedFileURL = nil
                                    backupMetadata = nil
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.vertical, 32)
                        } else if importSuccess {
                            // Success state
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.green.opacity(0.8))

                                Text("Restore Complete!")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("Your data has been restored successfully")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)

                                Button("Done") {
                                    Haptics.tap()
                                    dismiss()
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 32)
                        } else if let metadata = backupMetadata {
                            // Preview state
                            previewSection(metadata: metadata)
                        } else {
                            // Initial state - select file
                            VStack(spacing: 20) {
                                warningSection

                                Button {
                                    Haptics.tap()
                                    showFilePicker = true
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.badge.plus")
                                            .font(.system(size: 15))
                                        Text("Select Backup File")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.blue.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .padding(.horizontal, 24)
                            }
                            .padding(.top, 20)
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.5))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result: result)
            }
            .alert("Confirm Restore", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {
                    Haptics.tap()
                }
                Button("Restore", role: .destructive) {
                    Haptics.tap()
                    Task {
                        await performRestore()
                    }
                }
            } message: {
                if mergeStrategy == .replaceAll {
                    Text("This will replace all your existing data with the backup. This action cannot be undone.")
                } else {
                    Text("This will merge the backup with your existing data. Duplicates will be skipped.")
                }
            }
        }
    }

    private var warningSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange.opacity(0.8))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Important")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Importing a backup can replace your existing data. Make sure you have a recent backup before proceeding.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .glassCard()
        .padding(.horizontal, 24)
    }

    private func previewSection(metadata: BackupMetadata) -> some View {
        VStack(spacing: 20) {
            // Backup info
            VStack(spacing: 16) {
                Text("Backup Preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    infoRow(label: "Created", value: metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                    AscendancyDivider()
                    infoRow(label: "Device", value: metadata.deviceName)
                    AscendancyDivider()
                    infoRow(label: "Protocols", value: "\(metadata.protocolCount)")
                    AscendancyDivider()
                    infoRow(label: "Dose Logs", value: "\(metadata.logCount)")
                    AscendancyDivider()
                    infoRow(label: "Documents", value: "\(metadata.documentCount)")
                }
                .glassCard()
            }
            .padding(.horizontal, 24)

            // Strategy picker
            VStack(spacing: 12) {
                Text("Import Strategy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    strategyOption(
                        title: "Replace All",
                        description: "Clear existing data and restore from backup",
                        strategy: .replaceAll,
                        isSelected: mergeStrategy == .replaceAll
                    )

                    AscendancyDivider()

                    strategyOption(
                        title: "Merge",
                        description: "Add backup data, keep existing data",
                        strategy: .merge,
                        isSelected: mergeStrategy == .merge
                    )
                }
                .glassCard()
            }
            .padding(.horizontal, 24)

            // Restore button
            Button {
                Haptics.tap()
                showConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15))
                    Text("Restore Backup")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.orange.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private func strategyOption(title: String, description: String, strategy: MergeStrategy, isSelected: Bool) -> some View {
        Button {
            Haptics.selection()
            mergeStrategy = strategy
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.3))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func handleFileSelection(result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file"
                return
            }

            selectedFileURL = url

            // Validate the backup
            Task {
                do {
                    let metadata = try await BackupService.shared.validateBackup(at: url)
                    backupMetadata = metadata
                    Haptics.success()
                } catch {
                    errorMessage = error.localizedDescription
                    Haptics.error()
                    url.stopAccessingSecurityScopedResource()
                }
            }
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
            Haptics.error()
        }
    }

    private func performRestore() async {
        guard let url = selectedFileURL else { return }

        isImporting = true
        errorMessage = nil

        do {
            try await BackupService.shared.restoreBackup(
                from: url,
                context: context,
                strategy: mergeStrategy
            ) { profile in
                // Restore profile data
                userName = profile.userName
                userGoal = profile.userGoal
                profileImageData = profile.profileImageData
            }

            url.stopAccessingSecurityScopedResource()
            importSuccess = true
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
            url.stopAccessingSecurityScopedResource()
        }

        isImporting = false
    }
}

#Preview {
    BackupImportView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self, MediaDocument.self], inMemory: true)
}
