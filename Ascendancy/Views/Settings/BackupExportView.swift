import SwiftUI
import SwiftData

struct BackupExportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @AppStorage("userGoal") private var userGoal = ""
    @AppStorage("profileImageData") private var profileImageData: Data?

    @State private var isCreatingBackup = false
    @State private var backupURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var estimatedSize: String = "Calculating..."

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Icon
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 32)

                        // Title
                        VStack(spacing: 8) {
                            Text("Export Backup")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Create a backup of all your data")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }

                        if isCreatingBackup {
                            // Progress indicator
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .tint(.white)

                                Text("Creating backup...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.vertical, 32)
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
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.vertical, 32)
                        } else if backupURL != nil {
                            // Success state
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.green.opacity(0.8))

                                Text("Backup Ready!")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("Your backup has been created successfully")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)

                                Button {
                                    Haptics.tap()
                                    showShareSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 15))
                                        Text("Share Backup")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.blue.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 32)
                        } else {
                            // Initial state
                            VStack(spacing: 20) {
                                infoSection

                                Button {
                                    Haptics.tap()
                                    Task {
                                        await createBackup()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.down.doc")
                                            .font(.system(size: 15))
                                        Text("Create Backup")
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
            .sheet(isPresented: $showShareSheet) {
                if let url = backupURL {
                    ShareSheet(items: [url])
                }
            }
        }
        .task {
            await calculateEstimatedSize()
        }
    }

    private var infoSection: some View {
        VStack(spacing: 16) {
            infoRow(icon: "info.circle", title: "What's Included", description: "All protocols, dose logs, media files, and profile data")
            AscendancyDivider()
            infoRow(icon: "lock.shield", title: "Your Data", description: "Backup stays on your device. Share only with people you trust")
            AscendancyDivider()
            infoRow(icon: "doc.text", title: "Estimated Size", description: estimatedSize)
        }
        .glassCard()
        .padding(.horizontal, 24)
    }

    private func infoRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
    }

    private func calculateEstimatedSize() async {
        do {
            let protocols = try context.fetch(FetchDescriptor<CompoundProtocol>())
            let logs = try context.fetch(FetchDescriptor<DoseLog>())
            let documents = try context.fetch(FetchDescriptor<MediaDocument>())

            var totalSize = 0
            for doc in documents {
                if let data = doc.imageData {
                    totalSize += data.count
                }
            }

            // Add estimated JSON size (rough estimate)
            totalSize += (protocols.count * 500) + (logs.count * 200) + (documents.count * 100)

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            estimatedSize = formatter.string(fromByteCount: Int64(totalSize))
        } catch {
            estimatedSize = "Unknown"
        }
    }

    private func createBackup() async {
        isCreatingBackup = true
        errorMessage = nil

        do {
            let url = try await BackupService.shared.createBackup(
                context: context,
                userName: userName,
                userGoal: userGoal,
                profileImageData: profileImageData
            )

            backupURL = url
            Haptics.success()

            // Auto-show share sheet
            try? await Task.sleep(for: .milliseconds(500))
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }

        isCreatingBackup = false
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Divider Component

private struct AscendancyDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}

#Preview {
    BackupExportView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self, MediaDocument.self], inMemory: true)
}
