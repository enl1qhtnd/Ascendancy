import SwiftUI

// MARK: - Log Dose Flow Sheet

struct LogDoseFlowSheet: View {
    let protocols: [CompoundProtocol]
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
                LogDosePickerContent(protocols: protocols) { protocol_ in
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
    let protocols: [CompoundProtocol]
    let onSelect: (CompoundProtocol) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                if protocols.isEmpty {
                    Spacer()
                    Text(catalogKey: "No active protocols")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(protocols) { p in
                                Button {
                                    Haptics.tap()
                                    onSelect(p)
                                } label: {
                                    LogDoseProtocolRow(protocol_: p)
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

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AscendancyTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}
