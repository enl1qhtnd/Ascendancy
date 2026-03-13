import SwiftUI
import SwiftData

struct ActiveProtocolsView: View {
    @Query private var protocols: [CompoundProtocol]
    @Environment(\.modelContext) private var context
    
    @State private var showNewProtocol = false
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedProtocol: CompoundProtocol? = nil
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
                                    Button {
                                        selectedProtocol = p
                                    } label: {
                                        ProtocolCard(protocol_: p) {
                                            protocolToLog = p
                                        }
                                    }
                                    .buttonStyle(.plain)
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
            .navigationDestination(item: $selectedProtocol) { p in
                ProtocolDetailView(protocol_: p)
            }
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
        Button(action: action) {
            Text(label)
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
