import SwiftMend
import Foundation

struct DiagnosticRecoveryModelProvider: RecoveryModelProviding {
    private let provider: any RecoveryModelProviding
    private let providerKind: DemoProviderKind

    init(
        wrapping provider: any RecoveryModelProviding,
        providerKind: DemoProviderKind
    ) {
        self.provider = provider
        self.providerKind = providerKind
    }

    init(wrapping provider: any RecoveryModelProviding) {
        self.init(wrapping: provider, providerKind: .hostedGemma)
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        do {
            return try await provider.recoveryAdvice(for: request)
        } catch {
            DemoResolutionLogger.record(
                modelFailure: DemoModelFailure(error: error),
                providerKind: providerKind
            )
            throw error
        }
    }
}

enum DemoModelFailure: Equatable, Sendable {
    case invalidConfiguration
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
    case transport(Int)
    case unexpected

    init(error: any Error) {
        switch error {
        case GemmaProviderError.invalidConfiguration:
            self = .invalidConfiguration
        case GemmaProviderError.invalidRequest:
            self = .invalidRequest
        case GemmaProviderError.invalidResponse:
            self = .invalidResponse
        case GemmaProviderError.httpStatus(let statusCode):
            self = .httpStatus(statusCode)
        case GeminiProviderError.invalidConfiguration:
            self = .invalidConfiguration
        case GeminiProviderError.invalidRequest:
            self = .invalidRequest
        case GeminiProviderError.invalidResponse:
            self = .invalidResponse
        case GeminiProviderError.httpStatus(let statusCode):
            self = .httpStatus(statusCode)
        case let error as URLError:
            self = .transport(error.errorCode)
        default:
            self = .unexpected
        }
    }
}
