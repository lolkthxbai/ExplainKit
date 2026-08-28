/// Supplies optional, contextual recovery advice when no approved rule matches.
public protocol RecoveryModelProviding: Sendable {
    func recoveryAdvice(for snapshot: ErrorSnapshot, context: RecoveryContext) async throws -> RecoveryAdvice
}

public enum RecoveryAdviceSource: Equatable, Sendable {
    case developerRule(id: String)
    case model
    case fallback
}

public struct RecoveryResolution: Equatable, Sendable {
    public let advice: RecoveryAdvice
    public let source: RecoveryAdviceSource

    public init(advice: RecoveryAdvice, source: RecoveryAdviceSource) {
        self.advice = advice
        self.source = source
    }
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
        await resolve(snapshot, context: context).advice
    }

    public func resolve(_ snapshot: ErrorSnapshot, context: RecoveryContext) async -> RecoveryResolution {
        if let rule = rules.first(where: { $0.matches(snapshot, context: context) }) {
            return RecoveryResolution(
                advice: rule.advice,
                source: .developerRule(id: rule.id)
            )
        }

        if let modelProvider, let advice = try? await modelProvider.recoveryAdvice(for: snapshot, context: context) {
            return RecoveryResolution(advice: advice, source: .model)
        }

        return RecoveryResolution(advice: fallbackAdvice, source: .fallback)
    }
}
