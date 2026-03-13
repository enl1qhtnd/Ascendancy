import SwiftUI
import SwiftData

// MARK: - Log Dose Sheet

struct LogDoseSheet: View {
    let protocol_: CompoundProtocol
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var doseAmount: String = ""
    @State private var doseUnit: DoseUnit = .mg
    @State private var timestamp = Date()
    @State private var notes = ""
    
    var isValid: Bool {
        guard let amount = NumericInputParser.parse(doseAmount) else { return false }
        return amount > 0
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Protocol info header
                    HStack(spacing: 12) {
                        CategoryIcon(category: protocol_.category, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(protocol_.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Scheduled: \(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                    }
                    .glassCard()
                    
                    // Dose input
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Dose")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        
                        HStack(spacing: 12) {
                            TextField(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2))), text: $doseAmount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            FormPicker(label: "", selection: $doseUnit, options: DoseUnit.allCases)
                                .frame(maxWidth: 80)
                        }
                        
                        Button("Use scheduled dose") {
                            doseAmount = "\(protocol_.doseAmount)"
                            doseUnit = protocol_.doseUnit
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    }
                    .glassCard()
                    
                    // Timestamp
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date & Time")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        DatePicker("", selection: $timestamp)
                            .labelsHidden()
                            .foregroundStyle(.white)
                            .tint(.white)
                    }
                    .glassCard()
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        TextField("Add a note...", text: $notes, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }
                    .glassCard()
                    
                    Spacer()
                    
                    Button {
                        logDose()
                    } label: {
                        Text("Log Dose")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isValid ? .black : .white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isValid ? Color.white : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!isValid)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Log Dose")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    private func logDose() {
        guard let amount = NumericInputParser.parse(doseAmount) else { return }
        
        let log = DoseLog(protocol_: protocol_, actualDoseAmount: amount, doseUnit: doseUnit, timestamp: timestamp, notes: notes)
        context.insert(log)
        
        // Decrement inventory (safe: already on MainActor)
        let warning = InventoryService.shared.decrementInventory(for: protocol_, dose: log)
        
        do {
            try context.save()
        } catch {
            print("[LogDoseSheet] Failed to save dose log: \(error)")
        }
        
        // Low inventory notification (fire-and-forget on MainActor)
        if case .some(let w) = warning {
            if case .low = w {
                Task { @MainActor in
                    await NotificationService.shared.sendLowInventoryAlert(for: protocol_)
                }
            }
        }
        
        dismiss()
    }
}
