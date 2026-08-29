import Foundation

private struct QuotaUsageHistoryFile: Codable, Sendable {
    let version: Int
    let samples: [QuotaUsageSample]
}

enum QuotaUsageHistoryStore {
    private static let version = 1
    private static let retention: TimeInterval = 35 * 24 * 60 * 60
    private static let maximumSamples = 5_000

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return support
            .appendingPathComponent("CodexTokenLedger", isDirectory: true)
            .appendingPathComponent("quota-observations-v1.json", isDirectory: false)
    }

    static func load(from url: URL = defaultURL) -> [QuotaUsageSample] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(QuotaUsageHistoryFile.self, from: data),
              file.version == version
        else { return [] }
        let cutoff = Date().addingTimeInterval(-retention)
        return file.samples.filter { $0.observedAt >= cutoff }.sorted { $0.observedAt < $1.observedAt }
    }

    static func samples(from snapshot: CodexAccountUsageSnapshot) -> [QuotaUsageSample] {
        let lifetimeTokens = snapshot.accountTokenUsage?.summary.lifetimeTokens
        return snapshot.allWindows.map { window in
            QuotaUsageSample(
                accountID: snapshot.id,
                windowID: window.id,
                observedAt: snapshot.updatedAt,
                usedPercent: window.clampedUsedPercent,
                resetsAt: window.resetsAt,
                windowMinutes: window.windowMinutes,
                lifetimeTokens: lifetimeTokens
            )
        }
    }

    static func appending(
        snapshot: CodexAccountUsageSnapshot,
        to existing: [QuotaUsageSample],
        now: Date = Date()
    ) -> [QuotaUsageSample] {
        let cutoff = now.addingTimeInterval(-retention)
        var result = existing.filter { $0.observedAt >= cutoff }
        for candidate in samples(from: snapshot) {
            if let index = result.lastIndex(where: {
                $0.accountID == candidate.accountID
                    && $0.windowID == candidate.windowID
                    && abs($0.observedAt.timeIntervalSince(candidate.observedAt)) < 30
            }) {
                result[index] = candidate
            } else {
                result.append(candidate)
            }
        }
        return Array(result.sorted { $0.observedAt < $1.observedAt }.suffix(maximumSamples))
    }

    static func removing(accountID: String, from existing: [QuotaUsageSample]) -> [QuotaUsageSample] {
        existing.filter { $0.accountID != accountID }
    }

    static func save(_ samples: [QuotaUsageSample], to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(QuotaUsageHistoryFile(version: version, samples: samples))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
