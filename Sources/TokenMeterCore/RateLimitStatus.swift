import Foundation

/// One rate-limit window (either the 5-hour session limit or the 7-day
/// weekly limit) as reported by Claude Code's `statusLine` hook payload.
public struct RateLimitWindow: Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

extension RateLimitWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = try container.decode(Double.self, forKey: .usedPercentage)
        let epochSeconds = try container.decode(Double.self, forKey: .resetsAt)
        resetsAt = Date(timeIntervalSince1970: epochSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercentage, forKey: .usedPercentage)
        try container.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
    }
}

/// Both rate-limit windows Claude Code tracks. Either may be absent
/// depending on plan and account state; `rate_limits` itself is absent
/// entirely for non-subscription (pay-per-token API key) usage.
public struct RateLimits: Codable, Equatable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public init(fiveHour: RateLimitWindow?, sevenDay: RateLimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// The full snapshot `statusline.sh` writes to `status.json`.
public struct StatusSnapshot: Equatable {
    public let capturedAt: Date
    public let rateLimits: RateLimits?

    public init(capturedAt: Date, rateLimits: RateLimits?) {
        self.capturedAt = capturedAt
        self.rateLimits = rateLimits
    }
}

extension StatusSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case rateLimits = "rate_limits"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let epochSeconds = try container.decode(Double.self, forKey: .capturedAt)
        capturedAt = Date(timeIntervalSince1970: epochSeconds)
        rateLimits = try container.decodeIfPresent(RateLimits.self, forKey: .rateLimits)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capturedAt.timeIntervalSince1970, forKey: .capturedAt)
        try container.encodeIfPresent(rateLimits, forKey: .rateLimits)
    }
}
