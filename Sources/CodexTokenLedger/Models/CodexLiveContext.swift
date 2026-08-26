import Foundation

enum CodexThreadTitleSource: String, Codable, Hashable, Sendable {
    case desktopCatalog
    case explicitName
    case stateTitle
    case firstUserMessage
    case preview

    var localizationKey: String {
        switch self {
        case .desktopCatalog: "task.source.desktopCatalog"
        case .explicitName: "task.source.explicitName"
        case .stateTitle: "task.source.stateTitle"
        case .firstUserMessage: "task.source.firstUserMessage"
        case .preview: "task.source.preview"
        }
    }
}

struct CodexThreadMetadata: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titleSource: CodexThreadTitleSource
    let projectPath: String?
}

/// One accepted model call in the current Codex turn. Cost must be calculated
/// per call because long-context multipliers are request-scoped.
struct CodexModelCallUsage: Hashable, Identifiable, Sendable {
    let id: String
    let timestamp: Date
    let model: String
    let usage: TokenUsage
    let cumulativeTaskUsage: TokenUsage
}

/// The latest accounting state emitted by one active Codex thread.
///
/// `lastRequest` is the latest model-call context. `currentTurnUsage` aggregates
/// every accepted model call after the latest task_started event. Both come from
/// Codex accounting events rather than reconstructed visible chat text.
struct CodexLiveContextSnapshot: Hashable, Identifiable, Sendable {
    let id: String
    let sourcePath: String
    let projectPath: String?
    let threadTitle: String?
    let titleSource: CodexThreadTitleSource?
    let turnID: String?
    let model: String
    let reasoningEffort: String?
    let updatedAt: Date
    let lastRequest: TokenUsage
    let currentTurnUsage: TokenUsage
    let currentTurnCalls: [CodexModelCallUsage]
    let taskTotal: TokenUsage
    let modelContextWindow: Int64?
    let duplicateEventsIgnored: Int
    let isTaskActive: Bool

    var contextTokens: Int64 { lastRequest.totalTokens }

    /// Input tokens in the latest model call. This is the number users expect
    /// when they ask how much prompt context is currently being sent.
    var contextInputTokens: Int64 { lastRequest.inputTokens }

    /// Public model capacity from the current OpenAI model card. This can be
    /// larger than the effective window Codex emits for one specific turn.
    var publishedContextWindow: Int64? {
        PricingCatalog.publishedContextWindow(for: model)
    }

    /// The capacity used by the primary model-limit gauge. Prefer the public
    /// model card for known models while retaining `modelContextWindow` as
    /// separate runtime evidence.
    var contextCapacityWindow: Int64? {
        publishedContextWindow ?? modelContextWindow
    }

    var contextUsedPercent: Double? {
        guard let contextCapacityWindow, contextCapacityWindow > 0 else { return nil }
        return min(100, max(0, Double(contextInputTokens) / Double(contextCapacityWindow) * 100))
    }

    var contextRemainingTokens: Int64? {
        contextCapacityWindow.map { max(0, $0 - contextInputTokens) }
    }

    var runtimeWindowDiffersFromPublished: Bool {
        guard let publishedContextWindow, let modelContextWindow else { return false }
        return publishedContextWindow != modelContextWindow
    }

    var projectName: String {
        guard let projectPath, !projectPath.isEmpty else { return "Codex" }
        return URL(fileURLWithPath: projectPath).lastPathComponent
    }

    var displayTitle: String { threadTitle ?? projectName }

    var titleSourceLocalizationKey: String {
        titleSource?.localizationKey ?? "task.source.projectDirectory"
    }

    func applying(_ metadata: CodexThreadMetadata?) -> CodexLiveContextSnapshot {
        guard let metadata else { return self }
        return CodexLiveContextSnapshot(
            id: id,
            sourcePath: sourcePath,
            projectPath: metadata.projectPath ?? projectPath,
            threadTitle: metadata.title,
            titleSource: metadata.titleSource,
            turnID: turnID,
            model: model,
            reasoningEffort: reasoningEffort,
            updatedAt: updatedAt,
            lastRequest: lastRequest,
            currentTurnUsage: currentTurnUsage,
            currentTurnCalls: currentTurnCalls,
            taskTotal: taskTotal,
            modelContextWindow: modelContextWindow,
            duplicateEventsIgnored: duplicateEventsIgnored,
            isTaskActive: isTaskActive
        )
    }
}
