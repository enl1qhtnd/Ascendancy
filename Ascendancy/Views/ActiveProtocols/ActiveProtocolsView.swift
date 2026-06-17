import SwiftUI
import SwiftData

struct ActiveProtocolsView: View {
    @Query(sort: CompoundProtocol.listSortDescriptors)
    private var protocols: [CompoundProtocol]
    @Environment(\.modelContext) private var context
    
    @State private var showNewProtocol = false
    @State private var showReconCalc = false
    @AppStorage("protocolListFilter") private var selectedFilter: FilterOption = .all
    @State private var protocolToLog: CompoundProtocol? = nil
    @State private var navPath: [UUID] = []

    private let protocolCardCornerRadius: CGFloat = 18
    
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
        NavigationStack(path: $navPath) {
            ZStack {
                AscendancyTheme.appBackground.ignoresSafeArea()
                
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
                        List {
                            ForEach(filtered) { p in
                                protocolRow(p)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                            }
                            // Reordering only makes sense against the full,
                            // unfiltered ordering — restrict it to the "All"
                            // filter so sub-views can't accidentally rewrite
                            // global sortOrder from a partial list.
                            .onMove(perform: selectedFilter == .all ? move : nil)
                        }
                        .listStyle(.plain)
                        .listRowSpacing(12)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.horizontal, 16, for: .scrollContent)
                        .contentMargins(.bottom, 24, for: .scrollContent)
                        .environment(\.defaultMinListRowHeight, 0)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Protocols")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Haptics.tap()
                        showReconCalc = true
                    } label: {
                        Image(systemName: "flask.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(Text(catalogKey: "Reconstitution Calculator"))
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
            .toolbarBackground(AscendancyTheme.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showNewProtocol) {
                NewProtocolView()
            }
            .sheet(isPresented: $showReconCalc) {
                ReconstitutionCalculatorView()
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
        // Outer Button drives navigation via the NavigationStack path. This
        // avoids List's automatic chevron + row-tap behavior that NavigationLink
        // would introduce, while still letting the inner Log Dose Button win
        // its own taps (SwiftUI routes the tap to the innermost Button).
        Button {
            navPath.append(p.id)
        } label: {
            ProtocolCard(protocol_: p) {
                protocolToLog = p
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: protocolCardCornerRadius, style: .continuous))
        .contentShape(
            .dragPreview,
            RoundedRectangle(cornerRadius: protocolCardCornerRadius, style: .continuous)
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = filtered
        reordered.move(fromOffsets: source, toOffset: destination)

        let filteredIds = Set(filtered.map(\.id))
        var iter = reordered.makeIterator()
        var newGlobal: [CompoundProtocol] = []
        newGlobal.reserveCapacity(protocols.count)
        for p in protocols {
            if filteredIds.contains(p.id) {
                if let next = iter.next() { newGlobal.append(next) }
            } else {
                newGlobal.append(p)
            }
        }

        for (idx, proto) in newGlobal.enumerated() {
            if proto.sortOrder != idx { proto.sortOrder = idx }
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
