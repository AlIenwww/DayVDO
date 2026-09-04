import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    func testEveryLocalizationContainsEveryStaticallyUsedKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources/DayVDO")
        let resourceRoot = sourceRoot.appendingPathComponent("Resources")
        let swiftFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
        var required = Set<String>()
        let usePattern = try NSRegularExpression(
            pattern: #"L10n\.(?:string|format)\(\s*\"((?:[^\"\\]|\\.)*)\""#
        )
        for path in swiftFiles {
            let text = try String(contentsOf: sourceRoot.appendingPathComponent(path), encoding: .utf8)
            required.formUnion(captures(in: text, using: usePattern))
        }
        required.formUnion(["今天的待办已完成", "已完成事项当前已隐藏。"])

        let pairPattern = try NSRegularExpression(
            pattern: #"\"((?:[^\"\\]|\\.)*)\"\s*="#
        )
        for language in ["zh-Hans", "zh-Hant", "en", "ja", "ko", "es", "fr", "de"] {
            let file = resourceRoot
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("Localizable.strings")
            let text = try String(contentsOf: file, encoding: .utf8)
            let keys = Set(captures(in: text, using: pairPattern))
            let missing = required.subtracting(keys)
            XCTAssertTrue(missing.isEmpty, "Missing \(language) keys: \(missing.sorted())")
        }
    }

    func testLocalizationFormatArgumentsMatchTheirKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceRoot = root.appendingPathComponent("Sources/DayVDO/Resources")
        let pairPattern = try NSRegularExpression(
            pattern: #"\"((?:[^\"\\]|\\.)*)\"\s*=\s*\"((?:[^\"\\]|\\.)*)\"\s*;"#
        )
        let placeholderPattern = try NSRegularExpression(pattern: #"%(?:lld|ld|d|@)"#)

        for language in ["zh-Hans", "zh-Hant", "en", "ja", "ko", "es", "fr", "de"] {
            let file = resourceRoot
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("Localizable.strings")
            let text = try String(contentsOf: file, encoding: .utf8)
            let fullRange = NSRange(text.startIndex..., in: text)
            for match in pairPattern.matches(in: text, range: fullRange) {
                guard let keyRange = Range(match.range(at: 1), in: text),
                      let valueRange = Range(match.range(at: 2), in: text) else { continue }
                let key = String(text[keyRange])
                let value = String(text[valueRange])
                XCTAssertEqual(
                    placeholderTokens(in: key, using: placeholderPattern),
                    placeholderTokens(in: value, using: placeholderPattern),
                    "Format mismatch for \(language): \(key)"
                )
            }
        }
    }

    private func captures(in text: String, using expression: NSRegularExpression) -> [String] {
        let fullRange = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func placeholderTokens(
        in text: String,
        using expression: NSRegularExpression
    ) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}
