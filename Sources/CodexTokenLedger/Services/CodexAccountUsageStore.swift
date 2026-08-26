import Foundation

enum CodexAccountUsageStore {
    private static let version = 1

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return support
            .appendingPathComponent("CodexTokenLedger", isDirectory: true)
            .appendingPathComponent("account-usage-v1.json", isDirectory: false)
    }

    static func load(from url: URL = defaultURL) -> [CodexAccountUsageSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let cache = try? decoder.decode(CodexAccountUsageCache.self, from: data),
              cache.version == version
        else { return [] }
        return cache.accounts.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func upserting(
        _ snapshot: CodexAccountUsageSnapshot,
        into accounts: [CodexAccountUsageSnapshot]
    ) -> [CodexAccountUsageSnapshot] {
        var result = accounts.filter { $0.id != snapshot.id }
        result.append(snapshot)
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(
        _ accounts: [CodexAccountUsageSnapshot],
        to url: URL = defaultURL
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(CodexAccountUsageCache(version: version, accounts: accounts))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
