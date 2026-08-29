import SwiftMend
import Foundation

struct DiagnosticRecoveryModelProvider: RecoveryModelProviding {
    private let provider: any RecoveryModelProviding

    init(wrapping provider: any RecoveryModelProviding) {
        self.provider = provider
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        do {
            return try await provider.recoveryAdvice(for: request)
        } catch {
            DemoResolutionLogger.record(modelFailure: DemoModelFailure(error: error))
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
        case let error as URLError:
            self = .transport(error.errorCode)
        default:
            self = .unexpected
        }
    }
}
