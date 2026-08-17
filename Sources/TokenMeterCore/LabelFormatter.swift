import Foundation

/// Which rate-limit window drives the compact menu bar label.
public enum LabelMetric: String, CaseIterable, Codable {
    case fiveHour
    case sevenDay
    case mostUrgent
}

public enum UrgencyLevel: Equatable {
    case normal
    case warning
    case critical
    case unknown
}

public struct CompactLabel: Equatable {
    public let text: String
    public let level: UrgencyLevel
    public let isStale: Bool
}

/// Turns a `StatusFileStore.LoadResult` into exactly what the menu bar
/// label should show. Pure function, no I/O, so every branch is a
/// one-line unit test.
public enum LabelFormatter {
    public static func compactLabel(for result: StatusFileStore.LoadResult, metric: LabelMetric) -> CompactLabel {
        switch result {
        case .notInstalled:
            return CompactLabel(text: "–", level: .unknown, isStale: false)

        case .decodeError:
            return CompactLabel(text: "!", level: .unknown, isStale: false)

        case .noRateLimitData(_, let isStale):
            return CompactLabel(text: "n/a", level: .unknown, isStale: isStale)

        case .ok(let snapshot, let isStale):
            guard let rateLimits = snapshot.rateLimits else {
                return CompactLabel(text: "n/a", level: .unknown, isStale: isStale)
            }
            guard let (prefix, value) = selectedWindow(rateLimits, metric: metric) else {
                return CompactLabel(text: "n/a", level: .unknown, isStale: isStale)
            }
            let text = "\(prefix) \(Int(value.rounded()))%"
            let level: UrgencyLevel = value > 80 ? .critical : (value >= 50 ? .warning : .normal)
            return CompactLabel(text: text, level: level, isStale: isStale)
        }
    }

    private static func selectedWindow(_ rateLimits: RateLimits, metric: LabelMetric) -> (String, Double)? {
        switch metric {
        case .fiveHour:
            return rateLimits.fiveHour.map { ("5h", $0.usedPercentage) }
        case .sevenDay:
            return rateLimits.sevenDay.map { ("7d", $0.usedPercentage) }
        case .mostUrgent:
            let five = rateLimits.fiveHour.map { ("5h", $0.usedPercentage) }
            let seven = rateLimits.sevenDay.map { ("7d", $0.usedPercentage) }
            switch (five, seven) {
            case (nil, nil): return nil
            case (let f?, nil): return f
            case (nil, let s?): return s
            case (let f?, let s?): return f.1 >= s.1 ? f : s
            }
        }
    }
}
