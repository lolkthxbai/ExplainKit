import Foundation

/// A hosted Gemini provider backed by the Gemini API `generateContent` endpoint.
public struct GeminiRecoveryModelProvider: RecoveryModelProviding {
    public static let defaultModel = "gemini-3.7-flash"

    private let provider: GoogleGenerateContentRecoveryProvider

    public init(apiKey: String, model: String = Self.defaultModel) throws {
        try self.init(apiKey: apiKey, model: model, client: URLSession.shared)
    }

    init(
        apiKey: String,
        model: String = Self.defaultModel,
        client: any RecoveryHTTPClient
    ) throws {
        do {
            provider = try GoogleGenerateContentRecoveryProvider(
                apiKey: apiKey,
                model: model,
                family: .gemini,
                options: .gemini,
                client: client
            )
        } catch let error as GoogleGenerateContentError {
            throw GeminiProviderError(error)
        }
    }

    public func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        do {
            return try await provider.recoveryAdvice(for: request)
        } catch let error as GoogleGenerateContentError {
            throw GeminiProviderError(error)
        }
    }
}

public enum GeminiProviderError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)

    init(_ error: GoogleGenerateContentError) {
        switch error {
        case .invalidConfiguration:
            self = .invalidConfiguration
        case .invalidRequest:
            self = .invalidRequest
        case .invalidResponse:
            self = .invalidResponse
        case .httpStatus(let statusCode):
            self = .httpStatus(statusCode)
        }
    }
}
