import SwiftUI
import SwiftData

struct LogsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DoseLog.timestamp, order: .reverse)
    private var logs: [DoseLog]
    
    @Query private var protocols: [CompoundProtocol]
    
    @State private var searchText = ""
    @State private var selectedProtocolFilter: CompoundProtocol? = nil
    @State private var showLogSheet = false
    @State private var selectedLogForEdit: DoseLog? = nil
    
    var filteredLogs: [DoseLog] {
        logs.filter { log in
            let logName = log.protocol_?.name ?? log.protocolName
            let matchesSearch = searchText.isEmpty ||
                logName.localizedCaseInsensitiveContains(searchText) ||
                log.notes.localizedCaseInsensitiveContains(searchText)
            let matchesProtocol = selectedProtocolFilter == nil || log.protocol_?.id == selectedProtocolFilter?.id
            return matchesSearch && matchesProtocol
        }
    }
    
    var groupedLogs: [(String, [DoseLog])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let groups = Dictionary(grouping: filteredLogs) { log in
            formatter.string(from: log.timestamp)
        }
        return groups.sorted { a, b in
            let df = DateFormatter()
            df.dateStyle = .medium
            let d1 = df.date(from: a.key) ?? Date.distantPast
            let d2 = df.date(from: b.key) ?? Date.distantPast
            return d1 > d2
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Protocol filter scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", isSelected: selectedProtocolFilter == nil) {
                                selectedProtocolFilter = nil
                            }
                            ForEach(protocols.filter { $0.status == .active }) { p in
                                FilterChip(label: p.name.components(separatedBy: " ").first ?? p.name,
                                           isSelected: selectedProtocolFilter?.id == p.id) {
                                    selectedProtocolFilter = (selectedProtocolFilter?.id == p.id) ? nil : p
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    
                    if filteredLogs.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(groupedLogs, id: \.0) { dateString, dayLogs in
                                Section {
                                    ForEach(dayLogs) { log in
                                        LogEntryRow(log: log)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteLog(log)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button {
                                                    selectedLogForEdit = log
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }
                                                .tint(.blue)
                                            }
                                    }
                                } header: {
                                    Text(dateString)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search logs...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Logs")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(filteredLogs.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedLogForEdit) { log in
                EditDoseSheet(log: log)
            }
        }
    }
    
    private func deleteLog(_ log: DoseLog) {
        context.delete(log)
        try? context.save()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.15))
            Text("No logs found")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let log: DoseLog
    
    var categoryColor: Color {
        log.protocol_?.category.uiColor ?? Color(white: 0.5)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(log.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 44)
            
            // Color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 3, height: 36)
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(log.protocol_?.name ?? log.protocolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(log.formattedDose)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    
                    if !log.notes.isEmpty {
                        Text("· \(log.notes)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green.opacity(0.6))
                .font(.system(size: 16))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    LogsView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
