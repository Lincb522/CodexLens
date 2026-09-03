import Foundation

/// Keeps high-frequency menu-bar polling cheap without weakening accounting
/// accuracy. Unchanged files and appends containing only chat/stream events
/// reuse the last exact snapshot. A full parse is triggered whenever appended
/// bytes contain an accounting, task-state, or model-context event.
actor CodexLiveContextMonitor {
    private struct CacheEntry {
        var fileSize: Int64
        var modifiedAt: Date?
        var snapshot: CodexLiveContextSnapshot?
        var usageCheckpoint: CodexConversationUsageCheckpoint?
    }

    private let reader = CodexLiveContextReader()
    private let maximumCandidateFiles = 24
    private let activeDiscoveryWindow: TimeInterval = 30 * 60
    private let boundaryOverlapBytes: Int64 = 256
    private var entries: [String: CacheEntry] = [:]
    private var fullParseCount = 0

    func readContexts(
        codexHome: URL,
        preferredSourcePaths: [String],
        maximumResults: Int,
        discover: Bool
    ) throws -> [CodexLiveContextSnapshot] {
        let preferred = preferredSourcePaths.map(URL.init(fileURLWithPath:))
        let preferredSet = Set(preferred.map(normalizedPath))
        let candidates: [URL]

        if discover {
            let sessions = codexHome.appendingPathComponent("sessions", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: sessions.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw CodexLiveContextReaderError.noSessionDirectory(sessions.path)
            }
            candidates = deduplicated(
                preferred + Array(recentJSONLFiles(in: sessions).prefix(maximumCandidateFiles))
            )
        } else {
            candidates = deduplicated(preferred)
        }

        var active: [CodexLiveContextSnapshot] = []
        var fallback: CodexLiveContextSnapshot?

        for file in candidates {
            if discover, !preferredSet.contains(normalizedPath(file)) {
                let modified = resourceValues(for: file)?.contentModificationDate ?? .distantPast
                guard Date().timeIntervalSince(modified) <= activeDiscoveryWindow else { continue }
            }
            guard let context = snapshot(for: file) else { continue }
            if fallback == nil || context.updatedAt > fallback!.updatedAt {
                fallback = context
            }
            if context.isTaskActive {
                active.append(context)
                if active.count >= max(1, maximumResults) { break }
            }
        }

        if active.isEmpty, let fallback { return [fallback] }
        return active.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fullParseCountForTesting() -> Int { fullParseCount }

    private func snapshot(for file: URL) -> CodexLiveContextSnapshot? {
        let path = normalizedPath(file)
        guard let values = resourceValues(for: file), values.isRegularFile == true else {
            entries.removeValue(forKey: path)
            return nil
        }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else {
            entries[path] = CacheEntry(
                fileSize: size,
                modifiedAt: values.contentModificationDate,
                snapshot: nil,
                usageCheckpoint: nil
            )
            return nil
        }

        if var cached = entries[path] {
            if size == cached.fileSize, values.contentModificationDate == cached.modifiedAt {
                return cached.snapshot
            }
            if size > cached.fileSize,
               !appendedBytesContainLiveEvidence(file: file, previousSize: cached.fileSize) {
                cached.fileSize = size
                cached.modifiedAt = values.contentModificationDate
                entries[path] = cached
                return cached.snapshot
            }
        }

        let previousCheckpoint: CodexConversationUsageCheckpoint?
        if let cached = entries[path], size > cached.fileSize {
            previousCheckpoint = cached.usageCheckpoint
        } else {
            previousCheckpoint = nil
        }

        fullParseCount += 1
        let result = reader.readResult(
            file: file,
            previousUsageCheckpoint: previousCheckpoint
        )
        entries[path] = CacheEntry(
            fileSize: size,
            modifiedAt: values.contentModificationDate,
            snapshot: result?.snapshot,
            usageCheckpoint: result?.usageCheckpoint
        )
        return result?.snapshot
    }

    private func appendedBytesContainLiveEvidence(file: URL, previousSize: Int64) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return true }
        defer { try? handle.close() }
        let offset = UInt64(max(0, previousSize - boundaryOverlapBytes))
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), !data.isEmpty else { return false }
            let appendBoundary = Int(UInt64(previousSize) - offset)
            return Self.liveEvidenceNeedles.contains { needle in
                let searchStart = max(0, appendBoundary - needle.count + 1)
                guard searchStart < data.endIndex,
                      let match = data.range(of: needle, in: searchStart..<data.endIndex)
                else { return false }
                return match.upperBound > appendBoundary
            }
        } catch {
            return true
        }
    }

    private func recentJSONLFiles(in root: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            files.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func resourceValues(for file: URL) -> URLResourceValues? {
        try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey])
    }

    private func deduplicated(_ files: [URL]) -> [URL] {
        var seen = Set<String>()
        return files.filter { seen.insert(normalizedPath($0)).inserted }
    }

    private func normalizedPath(_ file: URL) -> String {
        file.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static let liveEvidenceNeedles: [Data] = [
        "token_count", "turn_context", "task_started", "task_complete",
    ].flatMap { kind in
        [
            Data(("\"type\":\"" + kind + "\"").utf8),
            Data(("\"type\": \"" + kind + "\"").utf8),
        ]
    }
}
