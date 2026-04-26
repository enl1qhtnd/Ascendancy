import SwiftUI

struct ProtocolCard: View {
    let protocol_: CompoundProtocol
    var onLogDose: (() -> Void)? = nil
    
    var activeLevel: Double {
        PharmacokineticsEngine.currentLevel(for: protocol_, logs: protocol_.doseLogs ?? [])
    }
    
    var daysOfSupply: Double? {
        InventoryService.shared.daysOfSupply(for: protocol_)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                CategoryIcon(category: protocol_.category, size: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(protocol_.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        StatusBadge(status: protocol_.status)
                        PillTag(text: protocol_.category.rawValue)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("per dose")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            AscendancyDivider()
            
            // Info row: schedule, next dose
            HStack(spacing: 16) {
                InfoBit(icon: "calendar.badge.clock", label: "Schedule", value: protocol_.schedule.description)
                
                if let next = protocol_.nextDoseDate() {
                    InfoBit(icon: "clock.arrow.circlepath", label: "Next Dose", value: relativeTime(next))
                }
                
                InfoBit(icon: "timer", label: "Half-life", value: "\(protocol_.halfLifeValue.formatted(.number.precision(.fractionLength(0...1)))) \(protocol_.halfLifeUnit.rawValue)")
            }
            
            AscendancyDivider()
            
            // Inventory row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: protocol_.isLowInventory ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(protocol_.isLowInventory ? Color.orange : Color.white.opacity(0.4))
                        Text(catalogKey: "Inventory")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(protocol_.inventoryCount.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(protocol_.isLowInventory ? .orange : .white)
                        Text(catalogKey: protocol_.inventoryDisplayUnitLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                
                Spacer()
                
                if let days = daysOfSupply {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "\(Int(days))d supply"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                if let onLogDose {
                    Button(action: {
                        Haptics.tap()
                        onLogDose()
                    }) {
                        Label("Log Dose", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .glassCard(cornerRadius: 18, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    }
    
    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct InfoBit: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                Text(catalogKey: label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .textCase(.uppercase)
                    .tracking(0.3)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }
}

#Preview {
    ScrollView {
        ProtocolCard(protocol_: SampleData.makeSampleProtocols()[0]) {}
            .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
