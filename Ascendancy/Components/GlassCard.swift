import SwiftUI

// MARK: - Glass Card View Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    var tintOpacity: Double = 0.06
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(tintOpacity))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) -> some View {
        self.modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// Like glassCard but the glass background fills the full offered height (for equal-height paired cards).
    func glassCardFilling(cornerRadius: CGFloat = 16, padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ProtocolStatus
    
    var body: some View {
        Text(catalogKey: status.rawValue)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }
    
    var statusColor: Color {
        switch status {
        case .active: return .green
        case .paused: return .yellow
        case .completed: return .blue
        case .archived: return Color(white: 0.5)
        }
    }
}

// MARK: - Category Icon

struct CategoryIcon: View {
    let category: CompoundCategory
    var size: CGFloat = 32
    
    var body: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.18))
                .frame(width: size, height: size)
            Image(systemName: category.icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }
    
    var iconColor: Color {
        category.uiColor
    }
}

// MARK: - Stat Label

struct StatLabel: View {
    let value: String
    let label: String
    var valueFont: Font = .system(size: 22, weight: .bold, design: .rounded)
    var labelFont: Font = .system(size: 11, weight: .medium)
    var alignment: HorizontalAlignment = .leading
    
    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(valueFont)
                .foregroundStyle(.white)
            Text(catalogKey: label)
                .font(labelFont)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    var body: some View {
        HStack {
            Text(catalogKey: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            if let action {
                Button(LocalizedStringKey(actionLabel), action: action)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Tile Header

struct TileHeader: View {
    let icon: String
    let title: String
    var iconColor: Color = .white.opacity(0.5)
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(catalogKey: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
    }
}

// MARK: - Pill Tag

struct PillTag: View {
    let text: String
    var color: Color = .white.opacity(0.15)
    
    var body: some View {
        Text(catalogKey: text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Inventory Bar

struct InventoryBar: View {
    let current: Double
    let maxValue: Double
    var lowThreshold: Double = 0.2
    
    var fraction: Double {
        guard maxValue > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, current / maxValue))
    }
    
    var barColor: Color {
        if fraction <= lowThreshold { return .red }
        if fraction <= lowThreshold * 2 { return .orange }
        return .green
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor.opacity(0.8))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Divider

struct AscendancyDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
    }
}
