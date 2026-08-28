/// Supplies optional, contextual recovery advice when no approved rule matches.
public protocol RecoveryModelProviding: Sendable {
    func recoveryAdvice(for snapshot: ErrorSnapshot, context: RecoveryContext) async throws -> RecoveryAdvice
}

/// Resolves errors deterministically, preferring developer-approved advice.
public struct RecoveryEngine: Sendable {
    public let rules: [RecoveryRule]
    public let fallbackAdvice: RecoveryAdvice
    private let modelProvider: (any RecoveryModelProviding)?

    public init(
        rules: [RecoveryRule] = [],
        fallbackAdvice: RecoveryAdvice,
        modelProvider: (any RecoveryModelProviding)? = nil
    ) {
        self.rules = rules
        self.fallbackAdvice = fallbackAdvice
        self.modelProvider = modelProvider
    }

    public func recover(from snapshot: ErrorSnapshot, context: RecoveryContext) async -> RecoveryAdvice {
        if let rule = rules.first(where: { $0.matches(snapshot, context: context) }) {
            return rule.advice
        }

        if let modelProvider, let advice = try? await modelProvider.recoveryAdvice(for: snapshot, context: context) {
            return advice
        }

        return fallbackAdvice
    }
}
