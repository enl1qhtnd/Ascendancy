import Foundation

enum NumericInputParser {
    private static let decimalFormatters: [NumberFormatter] = [
        makeDecimalFormatter(localeIdentifier: Locale.current.identifier),
        makeDecimalFormatter(localeIdentifier: "en_US_POSIX")
    ]

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: " ", with: "")
        let candidates = [
            normalized,
            normalized.replacingOccurrences(of: ",", with: "."),
            normalized.replacingOccurrences(of: ".", with: ",")
        ].reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }

        for formatter in decimalFormatters {
            for candidate in candidates {
                if let number = formatter.number(from: candidate) {
                    return number.doubleValue
                }
            }
        }

        for candidate in candidates {
            if let value = Double(candidate) {
                return value
            }
        }

        return nil
    }

    private static func makeDecimalFormatter(localeIdentifier: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        return formatter
    }
}
