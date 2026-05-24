import SwiftUI

enum AscendancyTheme {
    static let cardFill = Color(white: 0.09)
    static let cardStroke = Color.white.opacity(0.06)
    static let surfaceInset = Color(white: 0.07)
    static let surfaceRaised = Color(white: 0.11)

    static let sectionTracking: CGFloat = 0.12
    static let labelTracking: CGFloat = 0.06

    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func title(size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func sectionLabel(size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func cardLabel(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func dataValue(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func dataLabel(size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func meta(size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    func ascendancyCardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AscendancyTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AscendancyTheme.cardStroke, lineWidth: 0.5)
                )
        )
    }

    func ascendancySectionHeading() -> some View {
        font(AscendancyTheme.sectionLabel())
            .foregroundStyle(.white.opacity(0.5))
            .tracking(AscendancyTheme.sectionTracking)
    }

    func ascendancyCardHeading(size: CGFloat = 12) -> some View {
        font(AscendancyTheme.cardLabel(size: size))
            .foregroundStyle(.white.opacity(0.5))
            .tracking(AscendancyTheme.labelTracking)
    }

    func ascendancyFieldLabel(size: CGFloat = 12) -> some View {
        font(AscendancyTheme.dataLabel(size: size))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(AscendancyTheme.labelTracking)
    }
}
