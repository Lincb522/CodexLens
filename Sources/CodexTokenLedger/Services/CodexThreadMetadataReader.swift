import Foundation

enum CodexThreadMetadataReaderError: AppLocalizedError {
    case sqliteFailed(String)

    var localizationKey: String { "error.thread.sqlite" }
    var localizationArguments: [CVarArg] {
        guard case .sqliteFailed(let message) = self else { return [] }
        return [message]
    }
}

/// Resolves the name users see in Codex. The desktop catalog is preferred over
/// the older state title, while the working-directory basename is intentionally
/// left to the UI as a last-resort project fallback.
struct CodexThreadMetadataReader: Sendable {
    private struct StateRow: Decodable {
        let id: String
        let title: String?
        let name: String?
        let first_user_message: String?
        let preview: String?
        let cwd: String?
    }

    private struct DesktopRow: Decodable {
        let thread_id: String
        let display_title: String?
        let cwd: String?
    }

    func readAll(codexHome: URL) throws -> [String: CodexThreadMetadata] {
        var result: [String: CodexThreadMetadata] = [:]
        var lastError: Error?

        let stateDB = codexHome.appendingPathComponent("state_5.sqlite")
        if FileManager.default.fileExists(atPath: stateDB.path) {
            do {
                let rows: [StateRow] = try query(
                    database: stateDB,
                    sql: """
                    SELECT id, title, name, first_user_message, preview, cwd
                    FROM threads;
                    """
                )
                for row in rows {
                    guard let resolved = resolveStateTitle(row) else { continue }
                    result[row.id] = CodexThreadMetadata(
                        id: row.id,
                        title: resolved.title,
                        titleSource: resolved.source,
                        projectPath: cleaned(row.cwd)
                    )
                }
            } catch {
                lastError = error
            }
        }

        let desktopDB = codexHome.appendingPathComponent("sqlite/codex-dev.db")
        if FileManager.default.fileExists(atPath: desktopDB.path) {
            do {
                let rows: [DesktopRow] = try query(
                    database: desktopDB,
                    sql: """
                    SELECT thread_id, display_title, cwd
                    FROM local_thread_catalog
                    ORDER BY CASE WHEN host_id = 'local' THEN 0 ELSE 1 END;
                    """
                )
                for row in rows where result[row.thread_id]?.titleSource != .desktopCatalog {
                    guard let title = cleaned(row.display_title) else { continue }
                    result[row.thread_id] = CodexThreadMetadata(
                        id: row.thread_id,
                        title: title,
                        titleSource: .desktopCatalog,
                        projectPath: cleaned(row.cwd) ?? result[row.thread_id]?.projectPath
                    )
                }
            } catch {
                lastError = error
            }
        }

        if result.isEmpty, let lastError { throw lastError }
        return result
    }

    func read(threadID: String, codexHome: URL) throws -> CodexThreadMetadata? {
        try readAll(codexHome: codexHome)[threadID]
    }

    private func resolveStateTitle(_ row: StateRow) -> (title: String, source: CodexThreadTitleSource)? {
        if let value = cleaned(row.name) { return (value, .explicitName) }
        if let value = cleaned(row.title) { return (value, .stateTitle) }
        if let value = cleaned(row.first_user_message) { return (value, .firstUserMessage) }
        if let value = cleaned(row.preview) { return (value, .preview) }
        return nil
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func query<Row: Decodable>(database: URL, sql: String) throws -> [Row] {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, sql]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Drain stdout before waiting. A real Codex catalog can exceed the pipe
        // buffer; wait-then-read deadlocks once sqlite3 blocks on a full pipe.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let rawMessage = String(
                data: errorOutput,
                encoding: .utf8
            ) ?? ""
            let trimmedMessage = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmedMessage.isEmpty
                ? "sqlite3 exited with \(process.terminationStatus)"
                : trimmedMessage
            throw CodexThreadMetadataReaderError.sqliteFailed(message)
        }
        if output.isEmpty { return [] }
        return try JSONDecoder().decode([Row].self, from: output)
    }
}
