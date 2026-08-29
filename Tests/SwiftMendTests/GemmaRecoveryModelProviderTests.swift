import Foundation
import Testing
@testable import SwiftMend

extension Tag {
    @Tag static var networking: Self
}

struct GemmaRecoveryModelProviderTests {
    private let approvedActions = [
        RecoveryAction(id: "check-wifi", title: "Check Wi-Fi"),
        RecoveryAction(id: "try-again", title: "Try Again"),
        RecoveryAction(id: "open-settings", title: "Open Settings"),
        RecoveryAction(id: "contact-support", title: "Contact Support")
    ]

    @Test("A valid raw actionIDs response maps to canonical actions", .tags(.networking))
    func validResponseBecomesAdvice() async throws {
        let recorder = RequestRecorder()
        let responseData = try responseData(
            text: #"{"title":"Check your connection","message":"Reconnect, then retry.","actionIDs":["check-wifi","try-again"]}"#
        )
        let client = StubHTTPClient { request in
            await recorder.record(request)
            return (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(
            apiKey: "test-api-key",
            model: "gemma-4-26b-a4b-it",
            client: client
        )

        let advice = try await provider.recoveryAdvice(for: modelRequest())
        let request = try #require(await recorder.request)
        let requestBody = try #require(request.httpBody)
        let requestJSON = try #require(String(data: requestBody, encoding: .utf8))

        #expect(advice.title == "Check your connection")
        #expect(advice.actions == Array(approvedActions.prefix(2)))
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemma-4-26b-a4b-it:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-api-key")
        #expect(requestJSON.contains("profile sync"))
        #expect(requestJSON.contains("check-wifi"))
        #expect(requestJSON.contains("Check Wi-Fi"))
        #expect(requestJSON.contains("approvedActions"))
        #expect(requestJSON.contains("actionIDs"))
        #expect(requestJSON.contains("thinkingLevel"))
        #expect(requestJSON.contains("minimal"))
        #expect(requestJSON.contains("\"temperature\":0"))
        #expect(requestJSON.contains("\"candidateCount\":1"))
        #expect(requestJSON.contains("responseMimeType") == false)
        #expect(requestJSON.contains("responseSchema") == false)
        #expect(requestJSON.contains("responseJsonSchema") == false)
    }

    @Test("A fenced actionIDs JSON response becomes recovery advice", .tags(.networking))
    func fencedJSONBecomesAdvice() async throws {
        let responseData = try responseData(
            text: """
            ```json
            {"title":"Change settings","message":"Open settings, then retry.","actionIDs":["open-settings","try-again"]}
            ```
            """
        )
        let client = StubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        let advice = try await provider.recoveryAdvice(for: modelRequest())

        #expect(advice.title == "Change settings")
        #expect(advice.actions == [approvedActions[2], approvedActions[1]])
    }

    @Test("An unknown action ID is rejected", .tags(.networking))
    func unknownActionIDIsRejected() async throws {
        try await expectInvalidResponse(
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["not-approved"]}"#
        )
    }

    @Test("Duplicate action IDs are rejected", .tags(.networking))
    func duplicateActionIDsAreRejected() async throws {
        try await expectInvalidResponse(
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["try-again","try-again"]}"#
        )
    }

    @Test("More than three action IDs are rejected", .tags(.networking))
    func excessiveActionIDsAreRejected() async throws {
        try await expectInvalidResponse(
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["check-wifi","try-again","open-settings","contact-support"]}"#
        )
    }

    @Test("The old arbitrary action-string format is rejected", .tags(.networking))
    func arbitraryActionStringsAreRejected() async throws {
        try await expectInvalidResponse(
            #"{"title":"Recover","message":"Choose an option.","actions":["Anything the model wants"]}"#
        )
    }

    @Test("Malformed model output is rejected", .tags(.networking))
    func malformedOutputIsRejected() async throws {
        try await expectInvalidResponse("not-json")
    }

    @Test("Malformed approved-action catalogs fail before networking", .tags(.networking))
    func malformedCatalogsAreRejected() async throws {
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: StubHTTPClient.unused)
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
            await #expect(throws: GemmaProviderError.invalidRequest) {
                try await provider.recoveryAdvice(for: modelRequest(approvedActions: catalog))
            }
        }
    }

    @Test("HTTP failures retain their status code", .tags(.networking))
    func httpFailureRetainsStatus() async throws {
        let client = StubHTTPClient { request in
            (Data(), try Self.httpResponse(for: request, statusCode: 429))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        await #expect(throws: GemmaProviderError.httpStatus(429)) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("Invalid configuration fails before networking", .tags(.networking))
    func invalidConfigurationFails() {
        #expect(throws: GemmaProviderError.invalidConfiguration) {
            try GemmaRecoveryModelProvider(apiKey: "", client: StubHTTPClient.unused)
        }
        #expect(throws: GemmaProviderError.invalidConfiguration) {
            try GemmaRecoveryModelProvider(apiKey: "test-api-key", model: "../../other-model", client: StubHTTPClient.unused)
        }
        #expect(throws: GemmaProviderError.invalidConfiguration) {
            try GemmaRecoveryModelProvider(apiKey: "test-api-key", model: "gemini-3.7-flash", client: StubHTTPClient.unused)
        }
    }

    private func expectInvalidResponse(_ text: String) async throws {
        let responseData = try responseData(text: text)
        let client = StubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        await #expect(throws: GemmaProviderError.invalidResponse) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    private func modelRequest(
        approvedActions: [RecoveryAction]? = nil
    ) -> RecoveryModelRequest {
        RecoveryModelRequest(
            snapshot: ErrorSnapshot(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                message: "Offline"
            ),
            context: RecoveryContext(feature: "profile sync"),
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

    private static func httpResponse(for request: URLRequest, statusCode: Int) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
    }
}

private struct StubHTTPClient: RecoveryHTTPClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let unused = StubHTTPClient { _ in
        Issue.record("Networking should not be reached.")
        return (Data(), URLResponse())
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}
