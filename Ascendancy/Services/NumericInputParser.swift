import Foundation

enum NumericInputParser {
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: " ", with: "")
        let candidates = Array(Set([
            normalized,
            normalized.replacingOccurrences(of: ",", with: "."),
            normalized.replacingOccurrences(of: ".", with: ",")
        ]))

        for localeIdentifier in [Locale.current.identifier, "en_US_POSIX"] {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: localeIdentifier)
            formatter.numberStyle = .decimal

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
}
