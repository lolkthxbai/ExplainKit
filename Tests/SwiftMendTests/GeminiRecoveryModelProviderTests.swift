import Foundation
import Testing
@testable import SwiftMend

struct GeminiRecoveryModelProviderTests {
    private let approvedActions = [
        RecoveryAction(id: "choose-store", title: "Choose an in-stock store"),
        RecoveryAction(id: "choose-color", title: "Choose a different color"),
        RecoveryAction(id: "notify", title: "Notify me when available"),
        RecoveryAction(id: "cancel", title: "Cancel")
    ]

    @Test("Gemini requests structured output without exposing the API key", .tags(.networking))
    func requestUsesStructuredOutputSafely() async throws {
        let recorder = GeminiRequestRecorder()
        let responseData = try responseData(
            text: #"{"title":"Inventory changed","message":"Choose another available option.","actionIDs":["choose-store","choose-color"]}"#
        )
        let client = GeminiStubHTTPClient { request in
            await recorder.record(request)
            return (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        let advice = try await provider.recoveryAdvice(for: modelRequest())
        let request = try #require(await recorder.request)
        let body = try #require(request.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let contents = try #require(json["contents"] as? [[String: Any]])
        let userContent = try #require(contents.first)
        let userParts = try #require(userContent["parts"] as? [[String: Any]])
        let userPrompt = try #require(userParts.first?["text"] as? String)
        let generationConfig = try #require(json["generationConfig"] as? [String: Any])
        let thinkingConfig = try #require(
            generationConfig["thinkingConfig"] as? [String: Any]
        )
        let responseJsonSchema = try #require(
            generationConfig["responseJsonSchema"] as? [String: Any]
        )
        let properties = try #require(responseJsonSchema["properties"] as? [String: Any])
        let actionIDs = try #require(properties["actionIDs"] as? [String: Any])
        let actionItems = try #require(actionIDs["items"] as? [String: Any])
        let firstAction = try #require(advice.actions.first)

        #expect(GeminiRecoveryModelProvider.defaultModel == "gemini-3.7-flash")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.7-flash:generateContent")
        #expect(request.url?.query == nil)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body.range(of: Data("test-api-key".utf8)) == nil)
        #expect(userPrompt.contains("DemoCheckout"))
        #expect(userPrompt.contains("checkout inventory"))
        #expect(userPrompt.contains("choose-store"))
        #expect(userPrompt.contains("Choose an in-stock store"))
        #expect(generationConfig["responseMimeType"] as? String == "application/json")
        #expect(thinkingConfig["thinkingLevel"] as? String == "low")
        #expect(generationConfig["temperature"] == nil)
        #expect(generationConfig["candidateCount"] == nil)
        #expect(generationConfig["maxOutputTokens"] as? Int == 512)
        #expect(responseJsonSchema["type"] as? String == "OBJECT")
        #expect(Set(responseJsonSchema["required"] as? [String] ?? []) == ["title", "message", "actionIDs"])
        #expect(actionIDs["type"] as? String == "ARRAY")
        #expect(actionIDs["minItems"] as? Int == 1)
        #expect(actionIDs["maxItems"] as? Int == 3)
        #expect(actionItems["type"] as? String == "STRING")
        #expect(actionItems["enum"] as? [String] == approvedActions.map(\.id))
        #expect(advice.title == "Inventory changed")
        #expect(advice.actions == Array(approvedActions.prefix(2)))
        #expect(firstAction.title == "Choose an in-stock store")
    }

    @Test("Gemini accepts fenced actionIDs JSON", .tags(.networking))
    func fencedJSONBecomesAdvice() async throws {
        let responseData = try responseData(
            text: """
            ```json
            {"title":"Choose another option","message":"The selected item changed.","actionIDs":["notify","choose-store"]}
            ```
            """
        )
        let client = GeminiStubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        let advice = try await provider.recoveryAdvice(for: modelRequest())

        #expect(advice.actions == [approvedActions[2], approvedActions[0]])
    }

    @Test(
        "Gemini rejects malformed model advice",
        .tags(.networking),
        arguments: [
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["unknown"]}"#,
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["notify","notify"]}"#,
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["choose-store","choose-color","notify","cancel"]}"#,
            #"{"title":"Recover","message":"Choose an option.","actionIDs":[]}"#,
            #"{"title":"","message":"Choose an option.","actionIDs":["notify"]}"#,
            #"{"title":"Recover","message":"","actionIDs":["notify"]}"#,
            #"{"title":"Recover","message":"Choose an option.","actions":["Anything"]}"#,
            "not-json"
        ]
    )
    func malformedAdviceIsRejected(_ text: String) async throws {
        let responseData = try responseData(text: text)
        let client = GeminiStubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        await #expect(throws: GeminiProviderError.invalidResponse) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("Gemini rejects malformed catalogs before networking", .tags(.networking))
    func malformedCatalogsAreRejected() async throws {
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: GeminiStubHTTPClient.unused
        )
        let malformedCatalogs = [
            [RecoveryAction(id: "", title: "Missing ID")],
            [RecoveryAction(id: "retry", title: "   ")],
            [
                RecoveryAction(id: "retry", title: "Try Again"),
                RecoveryAction(id: "retry", title: "Retry Request")
            ],
            []
        ]

        for catalog in malformedCatalogs {
            await #expect(throws: GeminiProviderError.invalidRequest) {
                try await provider.recoveryAdvice(
                    for: modelRequest(approvedActions: catalog)
                )
            }
        }
    }

    @Test("Gemini rejects non-Gemini and unsafe model identifiers")
    func invalidConfigurationFailsBeforeNetworking() {
        #expect(throws: GeminiProviderError.invalidConfiguration) {
            try GeminiRecoveryModelProvider(
                apiKey: "",
                client: GeminiStubHTTPClient.unused
            )
        }
        #expect(throws: GeminiProviderError.invalidConfiguration) {
            try GeminiRecoveryModelProvider(
                apiKey: "test-api-key",
                model: "gemma-4-26b-a4b-it",
                client: GeminiStubHTTPClient.unused
            )
        }
        #expect(throws: GeminiProviderError.invalidConfiguration) {
            try GeminiRecoveryModelProvider(
                apiKey: "test-api-key",
                model: "gemini-",
                client: GeminiStubHTTPClient.unused
            )
        }
        #expect(throws: GeminiProviderError.invalidConfiguration) {
            try GeminiRecoveryModelProvider(
                apiKey: "test-api-key",
                model: "gemini/../../other-model",
                client: GeminiStubHTTPClient.unused
            )
        }
    }

    @Test("Gemini retains HTTP status failures", .tags(.networking))
    func httpFailureRetainsStatus() async throws {
        let client = GeminiStubHTTPClient { request in
            (Data(), try Self.httpResponse(for: request, statusCode: 429))
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        await #expect(throws: GeminiProviderError.httpStatus(429)) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("Gemini rejects non-HTTP and malformed API responses", .tags(.networking))
    func invalidAPIResponsesAreRejected() async throws {
        let nonHTTPClient = GeminiStubHTTPClient { request in
            let url = try #require(request.url)
            return (
                Data(),
                URLResponse(
                    url: url,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        }
        let malformedClient = GeminiStubHTTPClient { request in
            (Data("{}".utf8), try Self.httpResponse(for: request, statusCode: 200))
        }
        let nonHTTPProvider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: nonHTTPClient
        )
        let malformedProvider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: malformedClient
        )

        await #expect(throws: GeminiProviderError.invalidResponse) {
            try await nonHTTPProvider.recoveryAdvice(for: modelRequest())
        }
        await #expect(throws: GeminiProviderError.invalidResponse) {
            try await malformedProvider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("Gemini preserves transport failures", .tags(.networking))
    func transportFailuresPropagate() async throws {
        let client = GeminiStubHTTPClient { _ in
            throw GeminiTransportError.offline
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        await #expect(throws: GeminiTransportError.offline) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("Gemini preserves cancellation", .tags(.networking))
    func cancellationPropagates() async throws {
        let client = GeminiStubHTTPClient { _ in
            throw CancellationError()
        }
        let provider = try GeminiRecoveryModelProvider(
            apiKey: "test-api-key",
            client: client
        )

        await #expect(throws: CancellationError.self) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    private func modelRequest(
        approvedActions: [RecoveryAction]? = nil
    ) -> RecoveryModelRequest {
        RecoveryModelRequest(
            snapshot: ErrorSnapshot(
                domain: "DemoCheckout",
                code: 4002,
                message: "The checkout request could not be completed."
            ),
            context: RecoveryContext(feature: "checkout inventory"),
            approvedActions: approvedActions ?? self.approvedActions
        )
    }

    private func responseData(text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "candidates": [
                ["content": ["parts": [["text": text]]]]
            ]
        ])
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int
    ) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }
}

private struct GeminiStubHTTPClient: RecoveryHTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let unused = GeminiStubHTTPClient { _ in
        Issue.record("Networking should not be reached.")
        return (Data(), URLResponse())
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private actor GeminiRequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private enum GeminiTransportError: Error {
    case offline
}
