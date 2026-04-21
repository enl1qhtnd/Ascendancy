import XCTest
@testable import Ascendancy

final class NumericInputParserTests: XCTestCase {

    // MARK: - Valid inputs

    func test_parse_usDecimal_returnsParsedValue() {
        XCTAssertEqual(NumericInputParser.parse("1.5"), 1.5)
    }

    func test_parse_europeanDecimal_returnsParsedValue() {
        // "1,5" is the European way of writing 1.5
        XCTAssertEqual(NumericInputParser.parse("1,5"), 1.5)
    }

    func test_parse_integer_returnsDoubleValue() {
        XCTAssertEqual(NumericInputParser.parse("100"), 100.0)
    }

    func test_parse_zero_returnsZero() {
        XCTAssertEqual(NumericInputParser.parse("0"), 0.0)
    }

    func test_parse_negativeValue_returnsParsedValue() {
        let result = NumericInputParser.parse("-5.5")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, -5.5, accuracy: 0.001)
    }

    func test_parse_leadingAndTrailingWhitespace_isTrimmed() {
        XCTAssertEqual(NumericInputParser.parse("  2.5  "), 2.5)
    }

    func test_parse_internalSpaces_areRemoved() {
        // "1 000" with space-as-thousands-separator → 1000
        let result = NumericInputParser.parse("1 000")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 1000.0, accuracy: 0.001)
    }

    func test_parse_smallFractionalValue() {
        XCTAssertEqual(NumericInputParser.parse("0.25"), 0.25, accuracy: 0.0001)
    }

    func test_parse_largeWholeNumber() {
        XCTAssertEqual(NumericInputParser.parse("1000000"), 1_000_000.0)
    }

    // MARK: - Invalid / empty inputs

    func test_parse_emptyString_returnsNil() {
        XCTAssertNil(NumericInputParser.parse(""))
    }

    func test_parse_whitespaceOnly_returnsNil() {
        XCTAssertNil(NumericInputParser.parse("   "))
    }

    func test_parse_alphabeticString_returnsNil() {
        XCTAssertNil(NumericInputParser.parse("abc"))
    }

    func test_parse_mixedAlphanumeric_returnsNil() {
        XCTAssertNil(NumericInputParser.parse("12abc"))
    }

    func test_parse_specialCharactersOnly_returnsNil() {
        XCTAssertNil(NumericInputParser.parse("!@#"))
    }

    // MARK: - Locale-robustness

    func test_parse_dotDecimalAlwaysWorks() {
        // Period-separated decimals should always parse regardless of system locale
        let result = NumericInputParser.parse("3.14")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 3.14, accuracy: 0.001)
    }

    func test_parse_commaDecimalAlwaysWorks() {
        // Comma-separated decimals should always parse regardless of system locale
        let result = NumericInputParser.parse("3,14")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 3.14, accuracy: 0.001)
    }

    func test_parse_typicalDoseAmounts() {
        // Representative real-world dose values
        let cases: [(String, Double)] = [
            ("0.5", 0.5),
            ("2.5", 2.5),
            ("10", 10.0),
            ("100", 100.0),
            ("250", 250.0),
        ]
        for (input, expected) in cases {
            let result = NumericInputParser.parse(input)
            XCTAssertNotNil(result, "Expected non-nil for input: \(input)")
            XCTAssertEqual(result!, expected, accuracy: 0.001, "Failed for input: \(input)")
        }
    }
}
