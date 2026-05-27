import SwiftUI
import SwiftData

enum LogDoseSheetPresentation {
    static let height: CGFloat = 610
}

// MARK: - Log Dose Sheet

struct LogDoseSheet: View {
    let protocol_: CompoundProtocol

    var body: some View {
        NavigationStack {
            LogDoseSheetContent(protocol_: protocol_)
        }
        .presentationDetents([.height(LogDoseSheetPresentation.height)])
        .presentationDragIndicator(.visible)
    }
}

struct LogDoseSheetContent: View {
    let protocol_: CompoundProtocol
    var onBack: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

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
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                    // Protocol info header
                    HStack(spacing: 12) {
                        CategoryIcon(category: protocol_.category, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(protocol_.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(
                                String(
                                    format: String(localized: "Scheduled: %@ %@"),
                                    protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2))),
                                    protocol_.doseUnit.rawValue
                                )
                            )
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                    }
                    .glassCard()
                    
                    // Dose input
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Dose")
                            .ascendancyCardHeading()
                        
                        HStack(spacing: 12) {
                            TextField(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2))), text: $doseAmount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            FormPicker(label: "", selection: $doseUnit, options: DoseUnit.allCases)
                                .frame(maxWidth: 80)
                        }
                        
                        Button("Use scheduled dose") {
                            Haptics.selection()
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
                            .ascendancyCardHeading()
                        DatePicker("", selection: $timestamp)
                            .labelsHidden()
                            .foregroundStyle(.white)
                            .tint(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .ascendancyCardHeading()
                        TextField("Add a note...", text: $notes, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }
                    .glassCard()
                    
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
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Log Dose")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if let onBack {
                        Button {
                            Haptics.tap()
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Button("Cancel") {
                            Haptics.tap()
                            close()
                        }
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
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
            Haptics.error()
            return
        }
        
        // Low inventory notification (fire-and-forget on MainActor)
        if case .some(let w) = warning {
            if case .low = w {
                Task { @MainActor in
                    await NotificationService.shared.sendLowInventoryAlert(for: protocol_)
                }
            }
        }
        
        Haptics.success()
        close()
    }
}

// MARK: - Edit Dose Sheet

struct EditDoseSheet: View {
    let log: DoseLog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var doseAmount: String = ""
    @State private var doseUnit: DoseUnit = .mg
    @State private var timestamp: Date = Date()
    @State private var notes: String = ""

    var isValid: Bool {
        guard let amount = NumericInputParser.parse(doseAmount) else { return false }
        return amount > 0
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    if let p = log.protocol_ {
                        HStack(spacing: 12) {
                            CategoryIcon(category: p.category, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Editing logged dose")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                        }
                        .glassCard()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Dose")
                            .ascendancyCardHeading()

                        HStack(spacing: 12) {
                            TextField("0", text: $doseAmount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(.white)

                            FormPicker(label: "", selection: $doseUnit, options: DoseUnit.allCases)
                                .frame(maxWidth: 80)
                        }
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date & Time")
                            .ascendancyCardHeading()
                        DatePicker("", selection: $timestamp)
                            .labelsHidden()
                            .foregroundStyle(.white)
                            .tint(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .ascendancyCardHeading()
                        TextField("Add a note...", text: $notes, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }
                    .glassCard()

                    Button {
                        saveEdits()
                    } label: {
                        Text("Save Changes")
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
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Dose")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.height(580)])
        .presentationDragIndicator(.visible)
        .onAppear {
            doseAmount = log.actualDoseAmount.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
            doseUnit = log.doseUnit
            timestamp = log.timestamp
            notes = log.notes
        }
    }

    private func saveEdits() {
        guard let amount = NumericInputParser.parse(doseAmount), amount > 0 else { return }
        guard let protocol_ = log.protocol_ else { return }

        let previousAmount = log.actualDoseAmount
        log.actualDoseAmount = amount
        log.doseUnit = doseUnit
        log.timestamp = timestamp
        log.notes = notes

        let warning = InventoryService.shared.adjustInventoryOnEdit(
            for: protocol_,
            previousAmount: previousAmount,
            updatedDose: log
        )

        do {
            try context.save()
        } catch {
            print("[EditDoseSheet] Failed to save edits: \(error)")
            Haptics.error()
            return
        }

        if case .some(let w) = warning, case .low = w {
            Task { @MainActor in
                await NotificationService.shared.sendLowInventoryAlert(for: protocol_)
            }
        }

        Haptics.success()
        dismiss()
    }
}
