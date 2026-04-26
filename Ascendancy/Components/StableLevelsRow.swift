import SwiftUI

/// Shows steady-state ("stable levels") progress for a compound protocol.
/// 0% = just started, 100% = at or past 5× half-life (clinically stable).
struct StableLevelsRow: View {
    let info: StableLevelInfo
    var color: Color = .white
    
    private var barFraction: Double { info.percentage / 100.0 }

    private func percentText(_ percentage: Double) -> String {
        (percentage / 100.0).formatted(.percent.precision(.fractionLength(0)))
    }
    
    /// Friendly label for how far along (e.g. "2.3 half-lives elapsed")
    private var subtitleText: String {
        if info.isStable {
            let n = info.halfLivesElapsed.formatted(.number.precision(.fractionLength(1)))
            return String(format: String(localized: "Stable — %@ half-lives"), n)
        }
        let remaining = Swift.max(0, 5.0 - info.halfLivesElapsed)
        return String(
            format: String(localized: "%1$.1f of 5 half-lives — %2$.1f remaining"),
            locale: .current,
            info.halfLivesElapsed,
            remaining
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(catalogKey: "Stable Levels")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                // Percentage badge
                HStack(spacing: 3) {
                    Text(percentText(info.percentage))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(info.isStable ? color : .white)
                    
                    if info.isStable {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(color)
                    }
                }
            }
            
            // Progress bar with milestone ticks
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.07))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.5), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * barFraction)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: barFraction)
                    
                    // Milestone tick marks at 50%, 75%, 97% (≈5×t½)
                    ForEach([0.50, 0.75, 0.969], id: \.self) { milestone in
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: 10)
                            .offset(x: geo.size.width * milestone)
                    }
                }
            }
            .frame(height: 8)
            
            // Tick labels
            HStack {
                Text(percentText(0))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
                Text(percentText(50))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
                    .offset(x: 4)    // align under 50% tick
                Spacer()
                Text(percentText(75))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(catalogKey: "Stable")
                    Text("≥ \(percentText(97))")
                }
                .font(.system(size: 9))
                .foregroundStyle(info.isStable ? color.opacity(0.7) : .white.opacity(0.2))
                .multilineTextAlignment(.trailing)
            }
            
            Text(subtitleText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 24) {
        StableLevelsRow(
            info: StableLevelInfo(percentage: 32, hoursOnProtocol: 96, halfLivesElapsed: 1.3),
            color: .orange
        )
        StableLevelsRow(
            info: StableLevelInfo(percentage: 75, hoursOnProtocol: 240, halfLivesElapsed: 3.0),
            color: Color(red: 0.45, green: 0.75, blue: 1.0)
        )
        StableLevelsRow(
            info: StableLevelInfo(percentage: 97, hoursOnProtocol: 600, halfLivesElapsed: 5.1),
            color: Color(white: 0.92)
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
