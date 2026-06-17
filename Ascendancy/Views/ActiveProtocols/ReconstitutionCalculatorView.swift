import SwiftUI

struct ReconstitutionCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Unit enum

    enum DoseUnit: String, CaseIterable {
        case mcg, mg, iu

        /// Multiplier to convert a value in this unit to mg.
        /// mcg → mg divides by 1000; mg stays as-is; IU is treated 1:1 with mg
        /// (the user selects IU when the vial is labelled in IU and the
        /// conversion factor is unknown or irrelevant to volume math).
        var toMgFactor: Double {
            switch self {
            case .mcg: return 1.0 / 1000.0
            case .mg:  return 1.0
            case .iu:  return 1.0   // 1 IU ≈ 1 mg for volume purposes
            }
        }

        var displayUnit: String {
            switch self {
            case .mcg: return "mcg"
            case .mg:  return "mg"
            case .iu:  return "IU"
            }
        }
    }

    // MARK: - State

    @State private var peptideAmount: Double = 10      // in current peptideUnit
    @State private var peptideUnit: DoseUnit = .mg
    @State private var diluentAmount: Double = 1       // mL
    @State private var targetDoseStr = ""              // in peptideUnit (same unit as peptide amount)
    @FocusState private var isTargetDoseFocused: Bool

    // Wheel step values
    private let diluentStep: Double = 0.5
    private let diluentRange: ClosedRange<Double> = 0.5...10

    // Per-unit wheel config for peptide amount
    private struct WheelConfig {
        let range: ClosedRange<Double>
        let step: Double
        let defaultValue: Double
    }

    private func wheelConfig(for unit: DoseUnit) -> WheelConfig {
        switch unit {
        case .mcg: return WheelConfig(range: 50...10000,  step: 50, defaultValue: 750)
        case .mg:  return WheelConfig(range: 1...50,      step: 1,  defaultValue: 10)
        case .iu:  return WheelConfig(range: 1...50,      step: 1,  defaultValue: 10)
        }
    }

    // MARK: - Computed results (all internal math in mg)

    private var peptideAmountMg: Double {
        peptideAmount * peptideUnit.toMgFactor
    }

    private var targetDoseMg: Double {
        (NumericInputParser.parse(targetDoseStr) ?? 0) * peptideUnit.toMgFactor
    }

    /// Concentration in the *peptide unit* per mL.
    private var concentration: Double? {
        guard peptideAmountMg > 0, diluentAmount > 0 else { return nil }
        return peptideAmount / diluentAmount   // (value in peptideUnit) / mL
    }

    private var doseVolume: Double? {
        guard peptideAmountMg > 0, diluentAmount > 0, targetDoseMg > 0 else { return nil }
        return targetDoseMg / (peptideAmountMg / diluentAmount)
    }

    private var doseVolumeInUnits: Double? {
        guard let vol = doseVolume else { return nil }
        return vol * 100
    }

    /// Total doses available in the vial at the target dose.
    private var totalDoses: Double? {
        guard targetDoseMg > 0 else { return nil }
        return peptideAmountMg / targetDoseMg
    }

    private var isValid: Bool {
        peptideAmountMg > 0 && diluentAmount > 0 && targetDoseMg > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AscendancyTheme.appBackground.ignoresSafeArea()

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
                                .ascendancyCardHeading()

                            VStack(spacing: 14) {
                                // Peptide Amount + Diluent Volume — side by side
                                HStack(alignment: .top, spacing: 12) {
                                    // Peptide Amount — wheel + unit picker
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(catalogKey: "Peptide Amount")
                                            .ascendancyFieldLabel(size: 11)

                                        let config = wheelConfig(for: peptideUnit)

                                        HStack(spacing: 0) {
                                            wheelPicker(
                                                value: Binding(
                                                    get: { peptideAmount },
                                                    set: { peptideAmount = roundToStep($0, step: config.step) }
                                                ),
                                                range: config.range,
                                                step: config.step,
                                                format: { v in
                                                    String(format: "%.0f", v)
                                                }
                                            )
                                            .frame(maxWidth: .infinity)

                                            unitPicker(selection: $peptideUnit)
                                        }
                                    }

                                    // Diluent Volume — wheel + mL label
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(catalogKey: "Diluent Volume")
                                            .ascendancyFieldLabel(size: 11)

                                        HStack(spacing: 0) {
                                            wheelPicker(
                                                value: $diluentAmount,
                                                range: diluentRange,
                                                step: diluentStep,
                                                format: { v in
                                                    v.truncatingRemainder(dividingBy: 1) == 0
                                                        ? String(format: "%.0f", v)
                                                        : String(format: "%.1f", v)
                                                }
                                            )
                                            .frame(maxWidth: .infinity)

                                            unitLabel("mL")
                                        }
                                    }
                                }

                                // Target Dose — text field, shares peptide unit
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(catalogKey: "Target Dose")
                                        .ascendancyFieldLabel(size: 11)

                                    HStack {
                                        TextField("e.g. 2.5", text: $targetDoseStr)
                                            .keyboardType(.decimalPad)
                                            .focused($isTargetDoseFocused)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)

                                        Text(peptideUnit.displayUnit)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.4))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .glassCard()

                        // Results
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Results")
                                .ascendancyCardHeading()

                            if isValid, let conc = concentration, let vol = doseVolume, let units = doseVolumeInUnits, let doses = totalDoses {
                                VStack(spacing: 12) {
                                    resultRow(
                                        icon: "infinity",
                                        label: "Total Doses",
                                        value: formatDoses(doses),
                                        color: .orange
                                    )
                                    AscendancyDivider()
                                    resultRow(
                                        icon: "drop.fill",
                                        label: "Concentration",
                                        value: formatConcentration(conc, unit: peptideUnit),
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
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(AscendancyTheme.surfaceRaised)
                                                RoundedRectangle(cornerRadius: 3)
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
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reconstitution Calculator")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(AscendancyTheme.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: peptideUnit) { oldUnit, newUnit in
                // Switching to/from mcg resets the value; mg ↔ IU preserves it
                let newConfig = wheelConfig(for: newUnit)
                if newUnit == .mcg || oldUnit == .mcg {
                    peptideAmount = newConfig.defaultValue
                } else {
                    // mg ↔ IU: keep value but snap to new step
                    peptideAmount = roundToStep(peptideAmount, step: newConfig.step)
                }
            }
        }
    }

    // MARK: - Helpers

    private func roundToStep(_ value: Double, step: Double) -> Double {
        (value / step).rounded() * step
    }

    private func formatConcentration(_ value: Double, unit: DoseUnit) -> String {
        switch unit {
        case .mcg:
            return String(format: "%.1f mcg/mL", value)
        case .mg:
            // Show more decimal places for small mg values
            return value < 1
                ? String(format: "%.3f mg/mL", value)
                : String(format: "%.2f mg/mL", value)
        case .iu:
            return String(format: "%.2f IU/mL", value)
        }
    }

    private func formatDoses(_ value: Double) -> String {
        // Round down — you can't take a partial final dose from the math
        let whole = Int(value)
        let suffix = whole == 1 ? "dose" : "doses"
        return "\(whole) \(suffix)"
    }

    // MARK: - Subviews

    /// A wheel-style picker for selecting a value within a range and step.
    private func wheelPicker(value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
        let strideValues = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))

        return Picker("", selection: Binding(
            get: {
                // Find closest match in stride values
                let current = value.wrappedValue
                let nearest = strideValues.min(by: { abs($0 - current) < abs($1 - current) }) ?? current
                return nearest
            },
            set: { newValue in
                value.wrappedValue = newValue
                Haptics.selection()
            }
        )) {
            ForEach(strideValues, id: \.self) { v in
                Text(format(v))
                    .font(.system(size: 18))
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 120)
        .clipped()
    }

    /// A compact unit picker (mcg / mg / IU).
    private func unitPicker(selection: Binding<DoseUnit>) -> some View {
        Menu {
            ForEach(DoseUnit.allCases, id: \.self) { unit in
                Button(unit.displayUnit) {
                    Haptics.selection()
                    selection.wrappedValue = unit
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.wrappedValue.displayUnit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private func unitLabel(_ text: String) -> some View {
        Text(catalogKey: text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ReconstitutionCalculatorView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
