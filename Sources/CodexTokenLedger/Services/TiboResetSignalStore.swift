import Foundation

enum TiboResetSignalStore {
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("CodexTokenLedger", isDirectory: true)
            .appendingPathComponent("tibo-reset-signal.json", isDirectory: false)
    }

    static func load(from url: URL = defaultURL) -> TiboResetMonitorSnapshot {
        guard let data = try? Data(contentsOf: url),
              let value = try? decoder.decode(TiboResetMonitorSnapshot.self, from: data)
        else { return .empty }
        return value
    }

    static func save(_ snapshot: TiboResetMonitorSnapshot, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}
