import SwiftUI

struct ReconstitutionCalculatorView: View {
    var prefillName: String = ""
    @Environment(\.dismiss) private var dismiss
    
    @State private var peptideName: String = ""
    @State private var peptideAmountStr = ""   // mg
    @State private var diluentAmountStr = ""   // mL
    @State private var targetDoseStr = ""      // mcg
    
    var peptideAmount: Double { NumericInputParser.parse(peptideAmountStr) ?? 0 }
    var diluentAmount: Double { NumericInputParser.parse(diluentAmountStr) ?? 0 }
    var targetDose: Double { NumericInputParser.parse(targetDoseStr) ?? 0 }
    
    var concentration: Double? {   // mcg per mL
        guard peptideAmount > 0, diluentAmount > 0 else { return nil }
        return (peptideAmount * 1000) / diluentAmount
    }
    
    var doseVolume: Double? {       // mL to inject
        guard let conc = concentration, conc > 0, targetDose > 0 else { return nil }
        return targetDose / conc
    }
    
    var doseVolumeInUnits: Double? {  // Insulin syringe units (1 mL = 100 units)
        guard let vol = doseVolume else { return nil }
        return vol * 100
    }
    
    var isValid: Bool {
        peptideAmount > 0 && diluentAmount > 0 && targetDose > 0
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Info banner
                        HStack(spacing: 12) {
                            Image(systemName: "flask.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reconstitution Calculator")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Calculate dosing volumes for peptides")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                        }
                        .glassCard()
                        
                        // Inputs
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Inputs")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(0.8)
                            
                            VStack(spacing: 14) {
                                inputField(label: "Peptide Name", placeholder: prefillName.isEmpty ? "e.g. BPC-157" : prefillName, text: $peptideName)
                                
                                HStack(spacing: 12) {
                                    inputField(label: "Peptide Amount", placeholder: "e.g. 5", unit: "mg", text: $peptideAmountStr)
                                    inputField(label: "Diluent Volume", placeholder: "e.g. 2", unit: "mL", text: $diluentAmountStr)
                                }
                                
                                inputField(label: "Target Dose", placeholder: "e.g. 500", unit: "mcg", text: $targetDoseStr)
                            }
                        }
                        .glassCard()
                        
                        // Results
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Results")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .textCase(.uppercase)
                                .tracking(0.8)
                            
                            if isValid, let conc = concentration, let vol = doseVolume, let units = doseVolumeInUnits {
                                VStack(spacing: 12) {
                                    resultRow(
                                        icon: "drop.fill",
                                        label: "Concentration",
                                        value: String(format: "%.1f mcg/mL", conc),
                                        color: .purple
                                    )
                                    AscendancyDivider()
                                    resultRow(
                                        icon: "syringe.fill",
                                        label: "Inject Volume",
                                        value: String(format: "%.3f mL", vol),
                                        color: .blue
                                    )
                                    AscendancyDivider()
                                    resultRow(
                                        icon: "ruler.fill",
                                        label: "Insulin Syringe",
                                        value: String(format: "%.1f units", units),
                                        color: .teal
                                    )
                                    
                                    // Visual syringe scale
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(String(format: String(localized: "Syringe Position (%lld / 100 units)"), Int(units.rounded())))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.4))
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.white.opacity(0.06))
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.teal.opacity(0.7))
                                                    .frame(width: geo.size.width * min(1, units / 100))
                                            }
                                        }
                                        .frame(height: 8)
                                    }
                                }
                            } else {
                                Text("Enter peptide amount, diluent volume, and target dose above to calculate.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.3))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            }
                        }
                        .glassCard()
                        
                        // Tips
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Tips", systemImage: "lightbulb.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.yellow.opacity(0.7))
                            
                            Text("• Use bacteriostatic water (BW) as diluent for extended shelf life\n• Reconstituted peptides should be stored at 2–8°C\n• Draw air = inject volume of air before drawing peptide")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineSpacing(4)
                        }
                        .glassCard()
                        
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reconstitution Calculator")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            if !prefillName.isEmpty { peptideName = prefillName }
        }
    }
    
    @ViewBuilder
    private func inputField(label: String, placeholder: String, unit: String? = nil, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(catalogKey: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.4)
            HStack {
                TextField(placeholder, text: text)
                    .keyboardType(unit != nil ? .decimalPad : .default)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                if let unit {
                    Text(catalogKey: unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
    
    private func resultRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(catalogKey: label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ReconstitutionCalculatorView(prefillName: "BPC-157")
        .preferredColorScheme(.dark)
}
