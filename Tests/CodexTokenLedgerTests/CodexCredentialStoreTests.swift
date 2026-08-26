import XCTest
@testable import CodexTokenLedger

final class CodexCredentialStoreTests: XCTestCase {
    func testImportsNativeOAuthJSONAtomicallyWithPrivatePermissions() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("profile/.codex", isDirectory: true)
        let data = authData(accountID: "account-a", accessToken: "secret-a")

        try CodexCredentialStore.install(data, in: home)

        XCTAssertEqual(try CodexCredentialStore.authData(in: home), data)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: home.appendingPathComponent("auth.json").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(CodexCredentialStore.stableAccountID(from: data)?.count, 24)
    }

    func testRejectsUnrelatedJSON() throws {
        let data = try JSONSerialization.data(withJSONObject: ["hello": "world"])
        XCTAssertThrowsError(try CodexCredentialStore.validate(data)) { error in
            XCTAssertEqual(error as? CodexCredentialStoreError, .unsupportedDocument)
        }
    }

    func testReplacingRuntimeAuthKeepsBackupProfileUsable() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let backup = root.appendingPathComponent("backup", isDirectory: true)
        let first = authData(accountID: "first", accessToken: "secret-first")
        let second = authData(accountID: "second", accessToken: "secret-second")
        try CodexCredentialStore.install(first, in: runtime)

        try CodexCredentialStore.copyAuth(from: runtime, to: backup)
        try CodexCredentialStore.install(second, in: runtime)

        XCTAssertEqual(try CodexCredentialStore.authData(in: backup), first)
        XCTAssertEqual(try CodexCredentialStore.authData(in: runtime), second)
    }

    func testMergedAuthPreservesUnrelatedFieldsAndDropsStaleCredentialFields() throws {
        let current = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": "stale-key",
            "tokens": ["access_token": "stale-access", "account_id": "stale-account"],
            "custom_setting": ["keep": true],
        ])
        let target = authData(accountID: "fresh-account", accessToken: "fresh-access")

        let merged = try CodexCredentialStore.mergedAuth(target: target, preserving: current)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
        let tokens = try XCTUnwrap(object["tokens"] as? [String: Any])

        XCTAssertEqual(tokens["access_token"] as? String, "fresh-access")
        XCTAssertEqual(tokens["account_id"] as? String, "fresh-account")
        XCTAssertEqual((object["custom_setting"] as? [String: Any])?["keep"] as? Bool, true)
        XCTAssertTrue(object["OPENAI_API_KEY"] is NSNull)
    }

    func testStableIDSupportsTokenOnlyAndAPIKeyProfiles() throws {
        let tokenOnly = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": ["access_token": "token-only-secret"],
        ])
        let apiKey = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": "sk-private-key",
        ])

        let tokenID = try XCTUnwrap(CodexCredentialStore.stableAccountID(from: tokenOnly))
        let apiKeyID = try XCTUnwrap(CodexCredentialStore.stableAccountID(from: apiKey))
        XCTAssertEqual(tokenID.count, 24)
        XCTAssertEqual(apiKeyID.count, 24)
        XCTAssertNotEqual(tokenID, apiKeyID)
        XCTAssertFalse(tokenID.contains("token-only-secret"))
        XCTAssertFalse(apiKeyID.contains("sk-private-key"))
    }

    private func authData(accountID: String, accessToken: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "OPENAI_API_KEY": NSNull(),
            "tokens": [
                "access_token": accessToken,
                "refresh_token": "refresh-\(accountID)",
                "id_token": "id-\(accountID)",
                "account_id": accountID,
            ],
        ], options: [.sortedKeys])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexCredentialStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
