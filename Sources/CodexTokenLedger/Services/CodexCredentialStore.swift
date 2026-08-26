import CryptoKit
import Foundation

enum CodexCredentialStoreError: AppLocalizedError, Equatable {
    case authFileMissing
    case fileTooLarge
    case invalidJSON
    case unsupportedDocument
    case credentialMismatch

    var localizationKey: String {
        switch self {
        case .authFileMissing: "error.credentials.authMissing"
        case .fileTooLarge: "error.credentials.fileTooLarge"
        case .invalidJSON: "error.credentials.invalidJSON"
        case .unsupportedDocument: "error.credentials.unsupported"
        case .credentialMismatch: "error.credentials.mismatch"
        }
    }
}

/// Handles Codex's native `auth.json` without ever serializing credential
/// values into app preferences or logs. Account profiles remain local and
/// readable only by the current macOS user.
enum CodexCredentialStore {
    static let authFileName = "auth.json"
    private static let maximumAuthFileBytes = 5 * 1_024 * 1_024

    static func validate(_ data: Data) throws {
        guard data.count <= maximumAuthFileBytes else {
            throw CodexCredentialStoreError.fileTooLarge
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexCredentialStoreError.invalidJSON
        }

        let apiKey = normalized(root["OPENAI_API_KEY"])
        let tokens = root["tokens"] as? [String: Any]
        let hasOAuthToken = ["access_token", "refresh_token", "id_token"]
            .contains { normalized(tokens?[$0]) != nil }
        guard apiKey != nil || hasOAuthToken else {
            throw CodexCredentialStoreError.unsupportedDocument
        }
    }

    static func authData(in codexHome: URL) throws -> Data {
        let url = codexHome.appendingPathComponent(authFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexCredentialStoreError.authFileMissing
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try validate(data)
        return data
    }

    static func hasUsableAuth(in codexHome: URL) -> Bool {
        (try? authData(in: codexHome)) != nil
    }

    /// Atomically installs a validated Codex auth document with mode 0600.
    static func install(_ data: Data, in codexHome: URL) throws {
        try validate(data)
        let manager = FileManager.default
        let existed = manager.fileExists(atPath: codexHome.path)
        try manager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        if !existed {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexHome.path)
        }

        let destination = codexHome.appendingPathComponent(authFileName, isDirectory: false)
        let temporary = codexHome.appendingPathComponent(
            ".auth.json.token-pulse-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        do {
            try data.write(to: temporary, options: [.atomic, .completeFileProtection])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    static func copyAuth(from sourceHome: URL, to destinationHome: URL) throws {
        try install(authData(in: sourceHome), in: destinationHome)
    }

    /// Preserves unrelated official/custom top-level fields while replacing
    /// the complete credential projection. This avoids stale tokens without
    /// discarding settings that newer Codex versions may add to auth.json.
    static func mergedAuth(target: Data, preserving current: Data?) throws -> Data {
        try validate(target)
        guard let targetObject = try JSONSerialization.jsonObject(with: target) as? [String: Any] else {
            throw CodexCredentialStoreError.invalidJSON
        }
        var merged = (try? current.flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }) ?? [:]
        for key in ["OPENAI_API_KEY", "tokens", "auth_mode", "last_refresh"] {
            merged.removeValue(forKey: key)
        }
        for (key, value) in targetObject { merged[key] = value }
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try validate(data)
        return data
    }

    /// Returns a stable, non-secret identifier for OAuth and API-key profiles.
    /// Prefer the official account ID, then JWT claims, then a one-way digest
    /// of the credential. This keeps token-only logins switchable across app
    /// launches without persisting the raw token anywhere except auth.json.
    static func stableAccountID(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tokens = root["tokens"] as? [String: Any]
        let accessToken = normalized(tokens?["access_token"] ?? tokens?["accessToken"])
        let idToken = normalized(tokens?["id_token"] ?? tokens?["idToken"])
        let accountID = normalized(tokens?["account_id"] ?? tokens?["accountId"])
        let idTokenAccountID = accountIDClaim(fromJWT: idToken)
        let accessTokenAccountID = accountIDClaim(fromJWT: accessToken)
        let accessTokenIdentity = accessToken.map { "oauth:\($0)" }
        let idTokenIdentity = idToken.map { "oauth-id:\($0)" }
        let apiKeyIdentity = normalized(root["OPENAI_API_KEY"]).map { "api-key:\($0)" }
        let identity = accountID
            ?? idTokenAccountID
            ?? accessTokenAccountID
            ?? accessTokenIdentity
            ?? idTokenIdentity
            ?? apiKeyIdentity
        guard let identity else { return nil }
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func accountIDClaim(fromJWT token: String?) -> String? {
        guard let token else { return nil }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let accountID = normalized(auth["chatgpt_account_id"] ?? auth["account_id"]) {
            return accountID
        }
        return normalized(claims["chatgpt_account_id"] ?? claims["account_id"])
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
