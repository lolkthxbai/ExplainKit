import Foundation
import SwiftMend

struct DemoFailureRecoveryModelProvider: RecoveryModelProviding {
    enum Failure: Equatable, Sendable {
        case unavailable
        case invalidResponse
    }

    let failure: Failure

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        switch failure {
        case .unavailable:
            throw URLError(.notConnectedToInternet)
        case .invalidResponse:
            return RecoveryAdvice(
                title: "Incomplete guidance",
                message: "",
                actions: []
            )
        }
    }
}
