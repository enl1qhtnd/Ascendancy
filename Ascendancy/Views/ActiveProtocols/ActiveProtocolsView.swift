import SwiftUI
import SwiftData

struct ActiveProtocolsView: View {
    @Query(sort: CompoundProtocol.listSortDescriptors)
    private var protocols: [CompoundProtocol]
    @Environment(\.modelContext) private var context
    
    @State private var showNewProtocol = false
    @State private var selectedFilter: FilterOption = .active
    @State private var protocolToLog: CompoundProtocol? = nil
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case paused = "Paused"
        case completed = "Completed"
        case archived = "Archived"
    }
    
    var filtered: [CompoundProtocol] {
        switch selectedFilter {
        case .all: return protocols
        case .active: return protocols.filter { $0.status == .active }
        case .paused: return protocols.filter { $0.status == .paused }
        case .completed: return protocols.filter { $0.status == .completed }
        case .archived: return protocols.filter { $0.status == .archived }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                FilterChip(label: option.rawValue, isSelected: selectedFilter == option) {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedFilter = option
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(filtered) { p in
                                    protocolRow(p)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Protocols")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Haptics.tap()
                        showNewProtocol = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showNewProtocol) {
                NewProtocolView()
            }
            .sheet(item: $protocolToLog) { p in
                LogDoseSheet(protocol_: p)
            }
            .navigationDestination(for: UUID.self) { id in
                if let p = protocols.first(where: { $0.id == id }) {
                    ProtocolDetailView(protocol_: p)
                }
            }
        }
    }
    
    @ViewBuilder
    private func protocolRow(_ p: CompoundProtocol) -> some View {
        let link = NavigationLink(value: p.id) {
            ProtocolCard(protocol_: p) {
                protocolToLog = p
            }
        }
        .buttonStyle(.plain)
        
        if selectedFilter == .all {
            link
                .draggable(p.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let s = items.first,
                          let draggedId = UUID(uuidString: s),
                          draggedId != p.id else { return false }
                    applyReorder(draggedId: draggedId, targetId: p.id)
                    return true
                }
        } else {
            link
        }
    }
    
    private func applyReorder(draggedId: UUID, targetId: UUID) {
        guard draggedId != targetId else { return }
        var ids = protocols.map(\.id)
        guard let from = ids.firstIndex(of: draggedId), let to = ids.firstIndex(of: targetId) else { return }
        ids.remove(at: from)
        let insertAt = from < to ? to - 1 : to
        ids.insert(draggedId, at: insertAt)
        let orderById = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        for proto in protocols {
            if let o = orderById[proto.id] {
                proto.sortOrder = o
            }
        }
        do {
            try context.save()
            Haptics.selection()
        } catch {
            print("[ActiveProtocolsView] reorder save failed: \(error)")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cross.vial")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.15))
            Text("No protocols yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("Tap + to create your first protocol")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(catalogKey: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
                .animation(.spring(response: 0.3), value: isSelected)
        }
    }
}

#Preview {
    ActiveProtocolsView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
