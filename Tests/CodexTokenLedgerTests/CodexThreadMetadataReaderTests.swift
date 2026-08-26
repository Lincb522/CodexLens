import Foundation
import XCTest
@testable import CodexTokenLedger

final class CodexThreadMetadataReaderTests: XCTestCase {
    func testDesktopCatalogTitleOverridesStateTitleAndStateRemainsFallback() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenLedger-title-tests-\(UUID().uuidString)", isDirectory: true)
        let sqliteDirectory = home.appendingPathComponent("sqlite", isDirectory: true)
        try FileManager.default.createDirectory(at: sqliteDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        try runSQLite(
            database: home.appendingPathComponent("state_5.sqlite"),
            sql: """
            CREATE TABLE threads (
              id TEXT PRIMARY KEY, title TEXT, name TEXT,
              first_user_message TEXT, preview TEXT, cwd TEXT
            );
            INSERT INTO threads VALUES
              ('thread-1', '旧状态标题', NULL, '第一条消息', '预览', '/Projects/One'),
              ('thread-2', '状态回退标题', NULL, '另一条消息', '预览', '/Projects/Two');
            """
        )
        try runSQLite(
            database: sqliteDirectory.appendingPathComponent("codex-dev.db"),
            sql: """
            CREATE TABLE local_thread_catalog (
              host_id TEXT, thread_id TEXT, display_title TEXT, cwd TEXT
            );
            INSERT INTO local_thread_catalog VALUES
              ('local', 'thread-1', '桌面任务标题', '/Projects/One');
            """
        )

        let metadata = try CodexThreadMetadataReader().readAll(codexHome: home)

        XCTAssertEqual(metadata["thread-1"]?.title, "桌面任务标题")
        XCTAssertEqual(metadata["thread-1"]?.titleSource, .desktopCatalog)
        XCTAssertEqual(metadata["thread-2"]?.title, "状态回退标题")
        XCTAssertEqual(metadata["thread-2"]?.titleSource, .stateTitle)
    }

    private func runSQLite(database: URL, sql: String) throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "sqlite error"
            throw NSError(domain: "CodexThreadMetadataReaderTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
