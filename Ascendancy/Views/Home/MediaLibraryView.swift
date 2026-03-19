import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers // For file types

struct MediaLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaDocument.dateAdded, order: .reverse) private var documents: [MediaDocument]
    
    // Photo picker
    @State private var selectedItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    
    // File Picker
    @State private var showFileImporter = false
    // Edit Mode
    @State private var isEditing = false
    @State private var selectedIds: Set<UUID> = []
    
    // Rename
    @State private var documentToRename: MediaDocument?
    @State private var renameText = ""
    
    // Full-screen image preview
    @State private var previewDocument: MediaDocument?
    
    // Helpers for edit mode layout
    private let iconSize: CGFloat = 40
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if documents.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(documents) { doc in
                                documentTile(for: doc)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Rename alert
            .alert("Rename", isPresented: Binding(
                get: { documentToRename != nil },
                set: { if !$0 { documentToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {
                    Haptics.tap()
                    documentToRename = nil
                }
                Button("Save") {
                    if let doc = documentToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        doc.title = renameText.trimmingCharacters(in: .whitespaces)
                        do {
                            try context.save()
                            Haptics.success()
                        } catch {
                            print("[MediaLibraryView] Failed to save rename: \(error)")
                            Haptics.error()
                        }
                    }
                    documentToRename = nil
                }
            } message: {
                Text("Enter a new name for this file.")
            }
            // Full-screen preview sheet
            .sheet(item: $previewDocument) { doc in
                ImagePreviewSheet(document: doc)
            }
            // Photo picker onChange
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    do {
                        if let data = try await newItem?.loadTransferable(type: Data.self) {
                            let doc = MediaDocument(imageData: data, fileExtension: "jpg")
                            context.insert(doc)
                            try context.save()
                            selectedItem = nil
                            await MainActor.run { Haptics.success() }
                        }
                    } catch {
                        print("[MediaLibraryView] Failed to import photo: \(error)")
                        await MainActor.run { Haptics.error() }
                    }
                }
            }
            // File Importer
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .jpeg, .png, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Must attempt read even when startAccessing returns false (some providers/locations);
                    // only call stop when start succeeded.
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    // Read synchronously while security scope is active; defer runs after this block.
                    let readResult: Result<(Data, String, String), Error> = {
                        do {
                            let data = try Data(contentsOf: url)
                            let title = url.deletingPathExtension().lastPathComponent
                            let ext = url.pathExtension.lowercased()
                            return .success((data, title, ext))
                        } catch {
                            return .failure(error)
                        }
                    }()
                    Task { @MainActor in
                        switch readResult {
                        case .success(let (data, title, ext)):
                            do {
                                let doc = MediaDocument(title: title, imageData: data, fileExtension: ext)
                                context.insert(doc)
                                try context.save()
                                Haptics.success()
                            } catch {
                                print("[MediaLibraryView] Failed to save imported file: \(error)")
                                Haptics.error()
                            }
                        case .failure(let error):
                            print("[MediaLibraryView] Failed to read imported file: \(error)")
                            Haptics.error()
                        }
                    }
                case .failure(let error):
                    print("Error importing file: \(error.localizedDescription)")
                }
            }
            // Photo Picker
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedItem,
                matching: .images
            )
        }
    }
    
    // MARK: - Document Cell
    
    @ViewBuilder
    private func documentTile(for doc: MediaDocument) -> some View {
        let isSelected = selectedIds.contains(doc.id)
        let isPDF = doc.fileExtension == "pdf"
        
        Button {
            if isEditing {
                Haptics.selection()
                if isSelected { selectedIds.remove(doc.id) }
                else { selectedIds.insert(doc.id) }
            } else {
                Haptics.tap()
                previewDocument = doc
            }
        } label: {
            HStack(spacing: 16) {
                // Leading Icon / Thumbnail
                ZStack {
                    if isPDF {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.15))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.red.opacity(0.8))
                                    .font(.system(size: 20))
                            )
                    } else if let data = doc.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: iconSize, height: iconSize)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        // Fallback generic doc
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: iconSize, height: iconSize)
                            .overlay(
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                                    .font(.system(size: 20))
                            )
                    }
                }
                
                // Titles / Date
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(doc.dateAdded.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Selection or chevron
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.blue : .white.opacity(0.3))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Haptics.tap()
                documentToRename = doc
                renameText = doc.title
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                context.delete(doc)
                do {
                    try context.save()
                    Haptics.warning()
                } catch {
                    print("[MediaLibraryView] Failed to delete document: \(error)")
                    Haptics.error()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .opacity(isEditing && isSelected ? 0.6 : 1)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Pictures & Documents")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        
        ToolbarItem(placement: .navigationBarLeading) {
            if isEditing {
                Button("Done") {
                    Haptics.tap()
                    withAnimation { isEditing = false; selectedIds.removeAll() }
                }
                .foregroundStyle(.white)
            } else {
                Button("Close") {
                    Haptics.tap()
                    dismiss()
                }
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            if isEditing {
                // Delete selected
                Button(role: .destructive) {
                    Haptics.warning()
                    deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(selectedIds.isEmpty ? .white.opacity(0.3) : .red)
                }
                .disabled(selectedIds.isEmpty)
            } else {
                HStack(spacing: 16) {
                    // Edit button
                    if !documents.isEmpty {
                        Button {
                            Haptics.tap()
                            withAnimation { isEditing = true }
                        } label: {
                            Text("Edit")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    // Add Menu
                    Menu {
                        Button {
                            Haptics.tap()
                            showPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            Haptics.tap()
                            showFileImporter = true
                        } label: {
                            Label("Choose File", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.15))
            Text("No Files Yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("Tap + to add protocol photos,\nbloodwork results, or documents.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func deleteSelected() {
        for doc in documents where selectedIds.contains(doc.id) {
            context.delete(doc)
        }
        do {
            try context.save()
        } catch {
            print("[MediaLibraryView] Failed to delete selected documents: \(error)")
            Haptics.error()
            return
        }
        selectedIds.removeAll()
        withAnimation { isEditing = false }
    }
}

// MARK: - Full-screen Image Preview

struct ImagePreviewSheet: View {
    let document: MediaDocument
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let data = document.imageData {
                if document.fileExtension == "pdf" {
                    PDFKitView(pdfData: data)
                        .edgesIgnoringSafeArea(.bottom) // let it go behind the bottom area
                } else if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(20)
                    .background(Color.black.opacity(document.fileExtension == "pdf" ? 0.4 : 0).clipShape(Circle())) // ensure visible over pdf
            }
        }
        .overlay(alignment: .bottom) {
            if document.title != "Untitled" {
                Text(document.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(document.fileExtension == "pdf" ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(document.fileExtension == "pdf" ? Color.white.opacity(0.8).clipShape(Capsule()) : Color.clear.clipShape(Capsule()))
                    .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    MediaLibraryView()
        .modelContainer(for: MediaDocument.self, inMemory: true)
}
