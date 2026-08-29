/// A deterministic stand-in for a future hosted or on-device model provider.
public struct MockRecoveryModelProvider: RecoveryModelProviding {
    public enum Failure: Error, Equatable, Sendable {
        case unavailable
    }

    private let result: Result<RecoveryAdvice, Failure>

    public init(returning advice: RecoveryAdvice) {
        self.result = .success(advice)
    }

    public init(failingWith failure: Failure = .unavailable) {
        self.result = .failure(failure)
    }

    public func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        try result.get()
    }
}
