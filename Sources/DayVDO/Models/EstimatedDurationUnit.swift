import Foundation

enum EstimatedDurationUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case hours, minutes, mixed

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .hours: L10n.string("小时")
        case .minutes: L10n.string("分钟")
        case .mixed: L10n.string("混合")
        }
    }

    @MainActor
    func formatted(_ minutes: Int) -> String {
        switch self {
        case .hours:
            L10n.format("%@ 小时", Self.hourText(minutes: minutes, locale: L10n.locale))
        case .minutes:
            L10n.format("%lld 分钟", minutes)
        case .mixed:
            if minutes < 60 { L10n.format("%lld 分钟", minutes) }
            else if minutes % 60 == 0 { L10n.format("%@ 小时", (minutes / 60).formatted(.number.locale(L10n.locale))) }
            else { L10n.format("%lld 小时 %lld 分钟", minutes / 60, minutes % 60) }
        }
    }

    static func hourText(minutes: Int, locale: Locale) -> String {
        (Decimal(minutes) / 60).formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...2)))
    }

    struct Input: Equatable {
        var hours = ""
        var minutes = ""

        init(minutes total: Int? = nil, unit: EstimatedDurationUnit = .mixed, locale: Locale = .current) {
            guard let total else { return }
            switch unit {
            case .hours: hours = EstimatedDurationUnit.hourText(minutes: total, locale: locale)
            case .minutes: minutes = String(total)
            case .mixed:
                hours = String(total / 60)
                minutes = String(total % 60)
            }
        }

        enum Value: Equatable {
            case empty, invalid, minutes(Int)
        }

        func value(in unit: EstimatedDurationUnit, locale: Locale) -> Value {
            let hours = hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let minutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
            if hours.isEmpty && minutes.isEmpty { return .empty }

            switch unit {
            case .hours:
                let pieces = hours.components(separatedBy: locale.decimalSeparator ?? ".")
                guard pieces.count <= 2, pieces.contains(where: { !$0.isEmpty }),
                      pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                      let decimal = Decimal(string: pieces.joined(separator: "."), locale: Locale(identifier: "en_US_POSIX"))
                else { return .invalid }
                var scaled = decimal * 60
                var rounded = Decimal()
                NSDecimalRound(&rounded, &scaled, 0, .plain)
                guard rounded >= 1, rounded <= Decimal(Int.max) else { return .invalid }
                return .minutes(NSDecimalNumber(decimal: rounded).intValue)
            case .minutes, .mixed:
                guard let h = Int(hours.isEmpty ? "0" : hours), h >= 0,
                      let m = Int(minutes.isEmpty ? "0" : minutes), m >= 0,
                      h <= (Int.max - m) / 60 else { return .invalid }
                let total = h * 60 + m
                return total > 0 ? .minutes(total) : .invalid
            }
        }
    }
}
