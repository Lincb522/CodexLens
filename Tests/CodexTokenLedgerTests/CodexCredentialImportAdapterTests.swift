import XCTest
@testable import CodexTokenLedger

final class CodexCredentialImportAdapterTests: XCTestCase {
    func testDecodesSub2BatchIntoNativeCodexDocuments() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "type": "sub2api-data",
            "version": 1,
            "accounts": [
                [
                    "name": "alpha@example.com",
                    "platform": "openai",
                    "type": "oauth",
                    "credentials": [
                        "access_token": "access-alpha",
                        "refresh_token": "refresh-alpha",
                        "id_token": "id-alpha",
                        "chatgpt_account_id": "account-alpha",
                        "email": "alpha@example.com",
                        "plan_type": "pro",
                    ],
                ],
                [
                    "name": "beta@example.com",
                    "platform": "openai",
                    "type": "oauth",
                    "credentials": [
                        "access_token": "access-beta",
                        "refresh_token": "refresh-beta",
                        "chatgpt_account_id": "account-beta",
                        "email": "beta@example.com",
                    ],
                ],
            ],
        ])

        let imported = try CodexCredentialImportAdapter.decode(data)

        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.allSatisfy { $0.format == .sub2API })
        XCTAssertEqual(Set(imported.compactMap(\.email)), ["alpha@example.com", "beta@example.com"])
        for credential in imported {
            XCTAssertNoThrow(try CodexCredentialStore.validate(credential.authData))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: credential.authData) as? [String: Any])
            XCTAssertEqual(object["auth_mode"] as? String, "chatgpt")
            XCTAssertNotNil((object["tokens"] as? [String: Any])?["account_id"])
        }
    }

    func testDecodesCPAFlatAndListDocuments() throws {
        let flat: [String: Any] = [
            "type": "codex",
            "account_id": "cpa-account",
            "email": "cpa@example.com",
            "plan_type": "plus",
            "access_token": "cpa-access",
            "refresh_token": "cpa-refresh",
            "id_token": "cpa-id",
        ]
        let flatImported = try CodexCredentialImportAdapter.decode(
            JSONSerialization.data(withJSONObject: flat)
        )
        XCTAssertEqual(flatImported.count, 1)
        XCTAssertEqual(flatImported[0].format, .cpa)
        XCTAssertEqual(flatImported[0].email, "cpa@example.com")

        let list = try JSONSerialization.data(withJSONObject: [
            "type": "cliproxyapi-auth-list",
            "auths": [flat, flat],
        ])
        let listImported = try CodexCredentialImportAdapter.decode(list)
        XCTAssertEqual(listImported.count, 1, "Duplicate account IDs must be collapsed")
    }

    func testNativeAuthJSONRemainsNative() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": [
                "access_token": "native-access",
                "refresh_token": "native-refresh",
                "account_id": "native-account",
            ],
        ])
        let imported = try CodexCredentialImportAdapter.decode(data)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].format, .nativeCodex)
    }

    func testRejectsUnrelatedJSON() throws {
        let data = try JSONSerialization.data(withJSONObject: ["hello": "world"])
        XCTAssertThrowsError(try CodexCredentialImportAdapter.decode(data)) { error in
            XCTAssertEqual(error as? CodexCredentialImportError, .noSupportedAccounts)
        }
    }

    func testDecodesArbitrarilyNestedAliasesAndBearerHeader() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "export": [
                "payload": [
                    "provider": "OpenAI",
                    "display-name": "Primary Pro",
                    "account-email": "nested@example.com",
                    "authentication": [
                        "Authorization": "Bearer access-from-header",
                        "refreshToken": "refresh-from-camel-case",
                        "id-token": "id-from-kebab-case",
                        "chatgptAccountId": "nested-account",
                    ],
                ],
            ],
        ])

        let imported = try CodexCredentialImportAdapter.decode(data)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].format, .universalJSON)
        XCTAssertEqual(imported[0].email, "nested@example.com")
        let native = try XCTUnwrap(try JSONSerialization.jsonObject(with: imported[0].authData) as? [String: Any])
        let tokens = try XCTUnwrap(native["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["access_token"] as? String, "access-from-header")
        XCTAssertEqual(tokens["refresh_token"] as? String, "refresh-from-camel-case")
        XCTAssertEqual(tokens["id_token"] as? String, "id-from-kebab-case")
        XCTAssertEqual(tokens["account_id"] as? String, "nested-account")
    }

    func testDecodesCookieArrayStringifiedJSONAndJSONLines() throws {
        let cookieExport: [String: Any] = [
            "cookies": [
                ["name": "access_token", "value": "cookie-access"],
                ["name": "refresh-token", "value": "cookie-refresh"],
                ["name": "chatgpt_account_id", "value": "cookie-account"],
            ],
        ]
        let stringified = String(
            data: try JSONSerialization.data(withJSONObject: cookieExport),
            encoding: .utf8
        )!
        let wrapped = try JSONSerialization.data(withJSONObject: ["data": stringified])
        let wrappedImported = try CodexCredentialImportAdapter.decode(wrapped)
        XCTAssertEqual(wrappedImported.count, 1)

        let first = #"{"accessToken":"jsonl-access-a","accountId":"jsonl-a"}"#
        let second = #"{"access_token":"jsonl-access-b","account_id":"jsonl-b"}"#
        let jsonLines = try XCTUnwrap("\(first)\n\(second)".data(using: .utf8))
        let jsonLineImported = try CodexCredentialImportAdapter.decode(jsonLines)
        XCTAssertEqual(jsonLineImported.count, 2)
    }

    func testAcceptsRawOAuthTokenAndAPIKeyJSON() throws {
        let jwt = makeJWT(claims: [
            "email": "jwt@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "jwt-account"],
        ])
        let importedToken = try CodexCredentialImportAdapter.decode(text: "Bearer \(jwt)")
        XCTAssertEqual(importedToken.count, 1)
        XCTAssertEqual(importedToken[0].format, .rawToken)
        XCTAssertEqual(importedToken[0].email, "jwt@example.com")

        let apiKeyJSON = try JSONSerialization.data(withJSONObject: [
            "secrets": ["OPENAI-API-KEY": "sk-test-12345678901234567890"],
        ])
        let importedKey = try CodexCredentialImportAdapter.decode(apiKeyJSON)
        XCTAssertEqual(importedKey.count, 1)
        let native = try XCTUnwrap(try JSONSerialization.jsonObject(with: importedKey[0].authData) as? [String: Any])
        XCTAssertEqual(native["OPENAI_API_KEY"] as? String, "sk-test-12345678901234567890")
        XCTAssertEqual(native["auth_mode"] as? String, "apikey")
    }

    func testRejectsPlainTextThatIsNotAToken() {
        XCTAssertThrowsError(try CodexCredentialImportAdapter.decode(text: "hello world")) { error in
            XCTAssertEqual(error as? CodexCredentialImportError, .invalidToken)
        }
    }

    private func makeJWT(claims: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        func segment(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(segment(header)).\(segment(payload)).signature"
    }
}
