import Foundation
import Testing
@testable import SwiftMend

extension Tag {
    @Tag static var networking: Self
}

struct GemmaRecoveryModelProviderTests {
    @Test("A valid Gemma response becomes recovery advice", .tags(.networking))
    func validResponseBecomesAdvice() async throws {
        let recorder = RequestRecorder()
        let responseData = try responseData(
            text: #"{"title":"Check your connection","message":"Reconnect, then retry.","actions":["Check Wi-Fi","Try Again"]}"#
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

        let advice = try await provider.recoveryAdvice(
            for: ErrorSnapshot(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, message: "Offline"),
            context: RecoveryContext(feature: "profile sync")
        )
        let request = try #require(await recorder.request)
        let requestBody = try #require(request.httpBody)
        let requestJSON = try #require(String(data: requestBody, encoding: .utf8))

        #expect(advice.title == "Check your connection")
        #expect(advice.actions.map(\.title) == ["Check Wi-Fi", "Try Again"])
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemma-4-26b-a4b-it:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-api-key")
        #expect(requestJSON.contains("profile sync"))
        #expect(requestJSON.contains("thinkingLevel"))
    }

    @Test("A fenced JSON response becomes recovery advice", .tags(.networking))
    func fencedJSONBecomesAdvice() async throws {
        let responseData = try responseData(
            text: """
            ```json
            {"title":"Change delivery","message":"Select another option, then retry.","actions":["Change Delivery Option","Try Again"]}
            ```
            """
        )
        let client = StubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        let advice = try await provider.recoveryAdvice(
            for: ErrorSnapshot(domain: "DemoCheckout", code: 2001, message: "Checkout failed"),
            context: RecoveryContext(feature: "checkout")
        )

        #expect(advice.title == "Change delivery")
        #expect(advice.actions.map(\.title) == ["Change Delivery Option", "Try Again"])
    }

    @Test("Malformed model output is rejected", .tags(.networking))
    func malformedOutputIsRejected() async throws {
        let responseData = try responseData(text: "not-json")
        let client = StubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        do {
            _ = try await provider.recoveryAdvice(
                for: ErrorSnapshot(domain: "Demo", code: 1, message: "Failed"),
                context: RecoveryContext(feature: "demo")
            )
            Issue.record("Expected malformed output to be rejected.")
        } catch GemmaProviderError.invalidResponse {
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test("More than three actions are rejected", .tags(.networking))
    func excessiveActionsAreRejected() async throws {
        let responseData = try responseData(
            text: #"{"title":"Recover","message":"Choose an action.","actions":["One","Two","Three","Four"]}"#
        )
        let client = StubHTTPClient { request in
            (responseData, try Self.httpResponse(for: request, statusCode: 200))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        do {
            _ = try await provider.recoveryAdvice(
                for: ErrorSnapshot(domain: "Demo", code: 1, message: "Failed"),
                context: RecoveryContext(feature: "demo")
            )
            Issue.record("Expected excessive actions to be rejected.")
        } catch GemmaProviderError.invalidResponse {
        } catch {
            Issue.record("Wrong error thrown: \(error)")
        }
    }

    @Test("HTTP failures retain their status code", .tags(.networking))
    func httpFailureRetainsStatus() async throws {
        let client = StubHTTPClient { request in
            (Data(), try Self.httpResponse(for: request, statusCode: 429))
        }
        let provider = try GemmaRecoveryModelProvider(apiKey: "test-api-key", client: client)

        do {
            _ = try await provider.recoveryAdvice(
                for: ErrorSnapshot(domain: "Demo", code: 1, message: "Failed"),
                context: RecoveryContext(feature: "demo")
            )
            Issue.record("Expected an HTTP failure.")
        } catch GemmaProviderError.httpStatus(429) {
        } catch {
            Issue.record("Wrong error thrown: \(error)")
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
