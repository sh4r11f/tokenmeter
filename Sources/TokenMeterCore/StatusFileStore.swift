import Foundation

/// Reads and decodes the status.json file `statusline.sh` writes, and
/// classifies it (missing / fresh / stale / no-subscription-data /
/// unreadable) for the UI layer to render directly.
public struct StatusFileStore {
    public enum LoadResult: Equatable {
        case notInstalled
        case ok(StatusSnapshot, isStale: Bool)
        case noRateLimitData(capturedAt: Date, isStale: Bool)
        case decodeError(String)
    }

    public let statusFileURL: URL
    public let staleAfter: TimeInterval
    public let now: () -> Date

    public init(statusFileURL: URL, staleAfter: TimeInterval = 120, now: @escaping () -> Date = Date.init) {
        self.statusFileURL = statusFileURL
        self.staleAfter = staleAfter
        self.now = now
    }

    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: statusFileURL) else {
            return .notInstalled
        }
        do {
            let snapshot = try JSONDecoder().decode(StatusSnapshot.self, from: data)
            let age = now().timeIntervalSince(snapshot.capturedAt)
            let isStale = age > staleAfter
            if snapshot.rateLimits == nil {
                return .noRateLimitData(capturedAt: snapshot.capturedAt, isStale: isStale)
            }
            return .ok(snapshot, isStale: isStale)
        } catch {
            return .decodeError(String(describing: error))
        }
    }
}
