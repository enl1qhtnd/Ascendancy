import SwiftUI

// MARK: - Home Vitals Row

/// A horizontal row of circular "vital" stats shown in the home header,
/// mirroring the at-a-glance summary (RHR, Steps, Weight, Body Fat, Protocols).
struct HomeVitalsRow: View {
    @ObservedObject var healthKit: HealthKitService
    let protocolCount: Int

    private var rhrText: String {
        guard let v = healthKit.heartRateSamples.last?.value else { return "–" }
        return v.formatted(.number.precision(.fractionLength(0)))
    }

    private var stepsText: String {
        guard let v = healthKit.stepSamples.last?.value else { return "–" }
        if v >= 1000 {
            return "\((v / 1000).formatted(.number.precision(.fractionLength(0...1))))k"
        }
        return v.formatted(.number.precision(.fractionLength(0)))
    }

    private var weightText: String {
        guard let v = healthKit.latestWeight else { return "–" }
        let value = healthKit.displayWeight(v).formatted(.number.precision(.fractionLength(0)))
        let unit = healthKit.weightUnitIsLbs ? String(localized: "lbs") : String(localized: "kg")
        return "\(value) \(unit)"
    }

    private var bodyFatText: String {
        // Body fat samples are stored as a fraction (0...1) from HealthKit.
        guard let v = healthKit.bodyFatSamples.last?.value else { return "–" }
        return v.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                VitalCircle(icon: "heart", value: rhrText, label: "RHR")
                VitalCircle(icon: "shoeprints.fill", value: stepsText, label: "Steps")
                VitalCircle(icon: "scalemass", value: weightText, label: "Weight")
                VitalCircle(icon: "figure.arms.open", value: bodyFatText, label: "Body Fat")
                VitalCircle(icon: "cross.vial", value: "\(protocolCount)", label: "Protocols")
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Vital Circle

private struct VitalCircle: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.75)
                )
                .frame(width: 68, height: 68)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(value)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.top, 4)
                }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.12, blue: 0.32), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        HomeVitalsRow(healthKit: HealthKitService.shared, protocolCount: 3)
    }
    .preferredColorScheme(.dark)
}
