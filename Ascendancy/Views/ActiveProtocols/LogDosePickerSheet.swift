import SwiftUI

// MARK: - Log Dose Flow Sheet

struct LogDoseFlowSheet: View {
    let doses: [(CompoundProtocol, Date)]
    let logs: [DoseLog]
    @Environment(\.dismiss) private var dismissFlow
    @State private var selectedProtocol: CompoundProtocol?

    var body: some View {
        Group {
            if let protocol_ = selectedProtocol {
                NavigationStack {
                    LogDoseSheetContent(
                        protocol_: protocol_,
                        onBack: {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedProtocol = nil
                            }
                        },
                        onDismiss: { dismissFlow() }
                    )
                }
            } else {
                LogDosePickerContent(doses: doses, logs: logs) { protocol_ in
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedProtocol = protocol_
                    }
                }
            }
        }
        .presentationDetents([.height(LogDoseSheetPresentation.height)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Log Dose Picker Content

struct LogDosePickerContent: View {
    let doses: [(CompoundProtocol, Date)]
    let logs: [DoseLog]
    let onSelect: (CompoundProtocol) -> Void

    /// Most recent dose logged today for the protocol, if any.
    private func loggedDose(for p: CompoundProtocol) -> DoseLog? {
        let cal = Calendar.current
        return logs
            .filter { $0.protocol_?.id == p.id && cal.isDateInToday($0.timestamp) }
            .max { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        ZStack {
            AscendancyTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(catalogKey: "Log Dose")
                            .ascendancySectionHeading()
                            .foregroundStyle(.white.opacity(0.4))
                        Text(catalogKey: "Choose a protocol")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 35)
                .padding(.bottom, 20)

                if doses.isEmpty {
                    Spacer()
                    Text(catalogKey: "Nothing scheduled today")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(doses, id: \.0.id) { pair in
                                let (p, scheduledDate) = pair
                                let logEntry = loggedDose(for: p)
                                Button {
                                    Haptics.tap()
                                    onSelect(p)
                                } label: {
                                    LogDoseProtocolRow(
                                        protocol_: p,
                                        time: logEntry?.timestamp ?? scheduledDate,
                                        isLogged: logEntry != nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
    }
}

// MARK: - Protocol Row

private struct LogDoseProtocolRow: View {
    let protocol_: CompoundProtocol
    let time: Date
    let isLogged: Bool

    private var doseLabel: String {
        "\(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)"
    }

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(category: protocol_.category, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(protocol_.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(doseLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Text(time, format: .dateTime.hour().minute())
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            if isLogged {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.green.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AscendancyTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
