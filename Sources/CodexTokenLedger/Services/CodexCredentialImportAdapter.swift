import CryptoKit
import Foundation

enum CodexCredentialImportFormat: String, CaseIterable, Sendable {
    case nativeCodex = "Codex"
    case sub2API = "Sub2"
    case cpa = "CPA"
    case cockpit = "Cockpit"
    case universalJSON = "Token JSON"
    case rawToken = "Token"
}

struct ImportedCodexCredential: Sendable {
    let format: CodexCredentialImportFormat
    let authData: Data
    let accountID: String
    let email: String?
    let plan: String?
    let suggestedName: String?
}

enum CodexCredentialImportError: AppLocalizedError, Equatable {
    case invalidJSON
    case invalidToken
    case noSupportedAccounts
    case payloadTooLarge
    case tooManyAccounts

    var localizationKey: String {
        switch self {
        case .invalidJSON: "error.import.invalidJSON"
        case .invalidToken: "error.import.invalidToken"
        case .noSupportedAccounts: "error.import.noSupportedAccounts"
        case .payloadTooLarge: "error.import.payloadTooLarge"
        case .tooManyAccounts: "error.import.tooManyAccounts"
        }
    }
}

/// Converts native Codex, Sub2/sub2api, CPA/CLIProxyAPI, Cockpit and generic
/// token JSON into isolated native Codex `auth.json` documents. Recognition is
/// structural: key spelling is case/separator insensitive and credentials may
/// be nested in arbitrary envelopes or supplied as JSON Lines/stringified JSON.
/// Source payloads and credential values are never logged or persisted.
enum CodexCredentialImportAdapter {
    private struct Projection {
        var accessToken: String?
        var refreshToken: String?
        var idToken: String?
        var accountID: String?
        var apiKey: String?
        var email: String?
        var plan: String?
        var name: String?
        var lastRefresh: String?

        var hasCredential: Bool {
            apiKey != nil || accessToken != nil || refreshToken != nil || idToken != nil
        }

        mutating func fillMissing(from other: Projection) {
            accessToken = accessToken ?? other.accessToken
            refreshToken = refreshToken ?? other.refreshToken
            idToken = idToken ?? other.idToken
            accountID = accountID ?? other.accountID
            apiKey = apiKey ?? other.apiKey
            email = email ?? other.email
            plan = plan ?? other.plan
            name = name ?? other.name
            lastRefresh = lastRefresh ?? other.lastRefresh
        }
    }

    private static let maximumAccounts = 100
    private static let maximumCandidates = 1_000
    private static let maximumPayloadBytes = 10 * 1_024 * 1_024
    private static let maximumTraversalDepth = 24

    private static let accessAliases: Set<String> = [
        "accesstoken", "oauthaccesstoken", "bearertoken", "authtoken",
        "authorizationtoken", "openaiaccesstoken", "chatgptaccesstoken", "sessiontoken",
    ]
    private static let refreshAliases: Set<String> = [
        "refreshtoken", "oauthrefreshtoken", "openairefreshtoken", "chatgptrefreshtoken",
    ]
    private static let idTokenAliases: Set<String> = [
        "idtoken", "oauthidtoken", "openidtoken", "openaiidtoken",
    ]
    private static let accountAliases: Set<String> = [
        "accountid", "chatgptaccountid", "openaiaccountid", "useraccountid",
    ]
    private static let apiKeyAliases: Set<String> = [
        "openaiapikey", "apikey", "openaiapitoken",
    ]
    private static let credentialContainerAliases: Set<String> = [
        "tokens", "token", "credentials", "credential", "auth", "authentication",
        "oauth", "oauth2", "session", "secrets", "login", "authorization", "cookies",
    ]

    static func decode(_ data: Data) throws -> [ImportedCodexCredential] {
        guard data.count <= maximumPayloadBytes else {
            throw CodexCredentialImportError.payloadTooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexCredentialImportError.invalidJSON
        }

        if let root = parseJSON(data) {
            return try decodeRoot(root)
        }

        let nonEmptyLines = text.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let jsonLines = nonEmptyLines.compactMap { line -> Any? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lineData = trimmed.data(using: .utf8) else { return nil }
            return parseJSON(lineData)
        }
        if !jsonLines.isEmpty, jsonLines.count == nonEmptyLines.count {
            return try decodeRoot(jsonLines)
        }

        return try decodeRawToken(text)
    }

    static func decode(text: String) throws -> [ImportedCodexCredential] {
        guard let data = text.data(using: .utf8) else {
            throw CodexCredentialImportError.invalidToken
        }
        return try decode(data)
    }

    private static func decodeRoot(_ root: Any) throws -> [ImportedCodexCredential] {
        if let string = root as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nestedData = trimmed.data(using: .utf8), let nested = parseJSON(nestedData) {
                return try decodeRoot(nested)
            }
            return try decodeRawToken(trimmed)
        }

        var candidates: [(record: [String: Any], format: CodexCredentialImportFormat)] = []
        collect(root, inheritedFormat: nil, depth: 0, into: &candidates)
        guard !candidates.isEmpty else { throw CodexCredentialImportError.noSupportedAccounts }
        guard candidates.count <= maximumCandidates else { throw CodexCredentialImportError.tooManyAccounts }

        var results: [ImportedCodexCredential] = []
        var identifiers = Set<String>()
        for candidate in candidates {
            guard let converted = try convert(candidate.record, format: candidate.format) else { continue }
            if identifiers.insert(converted.accountID).inserted {
                results.append(converted)
                if results.count > maximumAccounts { throw CodexCredentialImportError.tooManyAccounts }
            }
        }
        guard !results.isEmpty else { throw CodexCredentialImportError.noSupportedAccounts }
        return results
    }

    private static func collect(
        _ value: Any,
        inheritedFormat: CodexCredentialImportFormat?,
        depth: Int,
        into results: inout [(record: [String: Any], format: CodexCredentialImportFormat)]
    ) {
        guard depth <= maximumTraversalDepth, results.count <= maximumCandidates else { return }
        if let string = value as? String,
           let data = string.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
           let nested = parseJSON(data) {
            collect(nested, inheritedFormat: inheritedFormat, depth: depth + 1, into: &results)
            return
        }
        if let array = value as? [Any] {
            let cookieObjects = array.compactMap { $0 as? [String: Any] }
            if cookieObjects.count == array.count,
               cookieObjects.contains(where: isCredentialCookie) {
                collect(["cookies": array], inheritedFormat: inheritedFormat, depth: depth + 1, into: &results)
                return
            }
            for item in array {
                collect(item, inheritedFormat: inheritedFormat, depth: depth + 1, into: &results)
            }
            return
        }
        guard let object = value as? [String: Any] else { return }

        let format = detectedFormat(object) ?? inheritedFormat ?? .universalJSON
        if hasCredentialSignal(object) {
            results.append((object, isNativeCodex(object) ? .nativeCodex : format))
        }

        for (key, child) in object
        where canonicalKey(key) != "cookies" && (child is [Any] || child is [String: Any] || child is String) {
            let childHint = wrapperFormat(key: key, object: object) ?? format
            collect(child, inheritedFormat: childHint, depth: depth + 1, into: &results)
        }
    }

    private static func convert(
        _ record: [String: Any],
        format: CodexCredentialImportFormat
    ) throws -> ImportedCodexCredential? {
        if format == .nativeCodex,
           let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           (try? CodexCredentialStore.validate(data)) != nil {
            let values = projection(from: record)
            let accountID = CodexCredentialStore.stableAccountID(from: data) ?? anonymousID(for: data)
            return ImportedCodexCredential(
                format: format,
                authData: data,
                accountID: accountID,
                email: values.email,
                plan: values.plan,
                suggestedName: values.name ?? values.email
            )
        }

        var values = projection(from: record)
        guard values.hasCredential else { return nil }
        values.accessToken = sanitizedSecret(values.accessToken)
        values.refreshToken = sanitizedSecret(values.refreshToken)
        values.idToken = sanitizedSecret(values.idToken)
        values.apiKey = sanitizedSecret(values.apiKey)

        let native: [String: Any]
        if let apiKey = values.apiKey, values.accessToken == nil, values.refreshToken == nil, values.idToken == nil {
            native = [
                "OPENAI_API_KEY": apiKey,
                "auth_mode": "apikey",
            ]
        } else {
            var nativeTokens: [String: Any] = [:]
            if let accessToken = values.accessToken { nativeTokens["access_token"] = accessToken }
            if let idToken = values.idToken { nativeTokens["id_token"] = idToken }
            if let refreshToken = values.refreshToken { nativeTokens["refresh_token"] = refreshToken }
            let rawAccountID = values.accountID
                ?? accountIDFromJWT(values.idToken)
                ?? accountIDFromJWT(values.accessToken)
            if let rawAccountID { nativeTokens["account_id"] = rawAccountID }
            native = [
                "OPENAI_API_KEY": NSNull(),
                "auth_mode": "chatgpt",
                "tokens": nativeTokens,
                "last_refresh": values.lastRefresh ?? ISO8601DateFormatter().string(from: Date()),
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: native, options: [.prettyPrinted, .sortedKeys])
        try CodexCredentialStore.validate(data)
        let stableID = CodexCredentialStore.stableAccountID(from: data) ?? anonymousID(for: data)
        return ImportedCodexCredential(
            format: format,
            authData: data,
            accountID: stableID,
            email: values.email ?? stringClaim("email", fromJWT: values.idToken) ?? stringClaim("email", fromJWT: values.accessToken),
            plan: values.plan,
            suggestedName: values.name ?? values.email
        )
    }

    private static func projection(from object: [String: Any], depth: Int = 0) -> Projection {
        guard depth <= maximumTraversalDepth else { return Projection() }
        var result = Projection(
            accessToken: value(in: object, aliases: accessAliases),
            refreshToken: value(in: object, aliases: refreshAliases),
            idToken: value(in: object, aliases: idTokenAliases),
            accountID: value(in: object, aliases: accountAliases),
            apiKey: value(in: object, aliases: apiKeyAliases),
            email: value(in: object, aliases: ["email", "useremail", "accountemail"]),
            plan: value(in: object, aliases: ["plan", "plantype", "chatgptplantype", "subscription"]),
            name: value(in: object, aliases: ["name", "label", "accountnote", "displayname"]),
            lastRefresh: value(in: object, aliases: ["lastrefresh", "refreshedat", "updatedat"])
        )

        if result.accessToken == nil, let authorization = value(in: object, aliases: ["authorization"]) {
            result.accessToken = sanitizedSecret(authorization)
        }

        // Cookie-manager exports commonly encode a token as {name, value}.
        if let cookieName = value(in: object, aliases: ["name", "key"]),
           let cookieValue = value(in: object, aliases: ["value", "content"]) {
            let normalizedName = canonicalKey(cookieName)
            if accessAliases.contains(normalizedName) { result.accessToken = result.accessToken ?? cookieValue }
            if refreshAliases.contains(normalizedName) { result.refreshToken = result.refreshToken ?? cookieValue }
            if idTokenAliases.contains(normalizedName) { result.idToken = result.idToken ?? cookieValue }
            if accountAliases.contains(normalizedName) { result.accountID = result.accountID ?? cookieValue }
        }

        let context = [
            value(in: object, aliases: ["type"]),
            value(in: object, aliases: ["provider", "platform", "service"]),
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        if result.accessToken == nil,
           (context.contains("oauth") || context.contains("openai") || context.contains("chatgpt") || object.count <= 4) {
            result.accessToken = value(in: object, aliases: ["token", "bearer", "access"])
            result.refreshToken = result.refreshToken ?? value(in: object, aliases: ["refresh"])
        }

        for (key, child) in object where credentialContainerAliases.contains(canonicalKey(key)) {
            if let dictionary = child as? [String: Any] {
                result.fillMissing(from: projection(from: dictionary, depth: depth + 1))
            } else if let array = child as? [Any] {
                for item in array {
                    if let dictionary = item as? [String: Any] {
                        result.fillMissing(from: projection(from: dictionary, depth: depth + 1))
                    }
                }
            } else if let string = child as? String,
                      let data = string.data(using: .utf8),
                      let nested = parseJSON(data) as? [String: Any] {
                result.fillMissing(from: projection(from: nested, depth: depth + 1))
            } else if let string = child as? String,
                      let token = sanitizedSecret(string),
                      looksLikeRawToken(token) {
                result.accessToken = result.accessToken ?? token
            }
        }
        return result
    }

    private static func hasCredentialSignal(_ object: [String: Any]) -> Bool {
        if isNativeCodex(object) { return true }
        if projection(from: object).hasCredential {
            let directKeys = Set(object.keys.map(canonicalKey))
            let knownKeys = accessAliases
                .union(refreshAliases)
                .union(idTokenAliases)
                .union(apiKeyAliases)
                .union(credentialContainerAliases)
                .union(["authorization", "access", "refresh"])
            if !directKeys.isDisjoint(with: knownKeys) { return true }
            if value(in: object, aliases: ["name", "key"]).map(canonicalKey).map({
                accessAliases.contains($0) || refreshAliases.contains($0) || idTokenAliases.contains($0)
            }) == true { return true }
        }
        return false
    }

    private static func isNativeCodex(_ object: [String: Any]) -> Bool {
        let keys = Set(object.keys.map(canonicalKey))
        if keys.contains("openaiapikey") { return true }
        guard keys.contains("tokens") else { return false }
        return projection(from: object).hasCredential
    }

    private static func detectedFormat(_ object: [String: Any]) -> CodexCredentialImportFormat? {
        let descriptor = [
            value(in: object, aliases: ["type"]),
            value(in: object, aliases: ["format"]),
            value(in: object, aliases: ["source"]),
            value(in: object, aliases: ["provider"]),
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        let keys = Set(object.keys.map(canonicalKey))
        if descriptor.contains("sub2") { return .sub2API }
        if descriptor.contains("cockpit") || keys.contains("accountnote") { return .cockpit }
        if descriptor.contains("cliproxy") || descriptor.contains("cpa") || keys.contains("auths") { return .cpa }
        if descriptor == "codex" || descriptor.hasPrefix("codex ") { return .cpa }
        if isNativeCodex(object) { return .nativeCodex }
        return nil
    }

    private static func isCredentialCookie(_ object: [String: Any]) -> Bool {
        guard let name = value(in: object, aliases: ["name", "key"]) else { return false }
        let key = canonicalKey(name)
        return accessAliases.contains(key)
            || refreshAliases.contains(key)
            || idTokenAliases.contains(key)
            || accountAliases.contains(key)
    }

    private static func wrapperFormat(key: String, object: [String: Any]) -> CodexCredentialImportFormat? {
        if let detected = detectedFormat(object) { return detected }
        switch canonicalKey(key) {
        case "accounts": return .sub2API
        case "auths": return .cpa
        case "profiles": return .cockpit
        default: return nil
        }
    }

    private static func decodeRawToken(_ text: String) throws -> [ImportedCodexCredential] {
        guard let token = sanitizedSecret(text), looksLikeRawToken(token) else {
            throw CodexCredentialImportError.invalidToken
        }
        let isAPIKey = token.lowercased().hasPrefix("sk-")
        let native: [String: Any] = isAPIKey
            ? ["OPENAI_API_KEY": token, "auth_mode": "apikey"]
            : [
                "OPENAI_API_KEY": NSNull(),
                "auth_mode": "chatgpt",
                "tokens": ["access_token": token],
                "last_refresh": ISO8601DateFormatter().string(from: Date()),
            ]
        let data = try JSONSerialization.data(withJSONObject: native, options: [.prettyPrinted, .sortedKeys])
        try CodexCredentialStore.validate(data)
        return [ImportedCodexCredential(
            format: .rawToken,
            authData: data,
            accountID: CodexCredentialStore.stableAccountID(from: data) ?? anonymousID(for: data),
            email: stringClaim("email", fromJWT: token),
            plan: nil,
            suggestedName: stringClaim("email", fromJWT: token)
        )]
    }

    private static func looksLikeRawToken(_ token: String) -> Bool {
        guard token.count >= 20, !token.contains(where: \.isWhitespace) else { return false }
        let lower = token.lowercased()
        return token.split(separator: ".", omittingEmptySubsequences: false).count >= 3
            || lower.hasPrefix("sk-")
            || lower.hasPrefix("eyj")
            || lower.hasPrefix("oauth-")
            || lower.hasPrefix("sess-")
    }

    private static func parseJSON(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func accountIDFromJWT(_ token: String?) -> String? {
        let payload = jwtPayload(token)
        if let auth = payload?["https://api.openai.com/auth"] as? [String: Any] {
            return first(auth["chatgpt_account_id"], auth["account_id"])
        }
        return first(payload?["chatgpt_account_id"], payload?["account_id"])
    }

    private static func stringClaim(_ name: String, fromJWT token: String?) -> String? {
        first(jwtPayload(token)?[name])
    }

    private static func jwtPayload(_ token: String?) -> [String: Any]? {
        guard let token = sanitizedSecret(token) else { return nil }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var encoded = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func value(in object: [String: Any], aliases: Set<String>) -> String? {
        for (key, rawValue) in object where aliases.contains(canonicalKey(key)) {
            if let value = normalized(rawValue) { return value }
        }
        return nil
    }

    private static func canonicalKey(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }

    private static func sanitizedSecret(_ value: String?) -> String? {
        guard var value = normalized(value) else { return nil }
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        return normalized(value)
    }

    private static func anonymousID(for data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func first(_ values: Any?...) -> String? {
        for value in values {
            if let normalized = normalized(value) { return normalized }
        }
        return nil
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
