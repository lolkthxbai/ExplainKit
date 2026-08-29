import Foundation

/// Supplies optional, contextual recovery advice when no approved rule matches.
public protocol RecoveryModelProviding: Sendable {
    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice
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
    public let approvedModelActions: [RecoveryAction]
    private let modelProvider: (any RecoveryModelProviding)?

    public init(
        rules: [RecoveryRule] = [],
        fallbackAdvice: RecoveryAdvice,
        approvedModelActions: [RecoveryAction] = [],
        modelProvider: (any RecoveryModelProviding)? = nil
    ) {
        self.rules = rules
        self.fallbackAdvice = fallbackAdvice
        self.approvedModelActions = approvedModelActions
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

        let request = RecoveryModelRequest(
            snapshot: snapshot,
            context: context,
            approvedActions: approvedModelActions
        )
        if let modelProvider,
           let catalog = try? request.validatedActionCatalog(),
           let advice = try? await modelProvider.recoveryAdvice(for: request),
           let validatedAdvice = validate(advice, against: catalog) {
            return RecoveryResolution(advice: validatedAdvice, source: .model)
        }

        return RecoveryResolution(advice: fallbackAdvice, source: .fallback)
    }

    private func validate(
        _ advice: RecoveryAdvice,
        against catalog: ValidatedRecoveryActionCatalog
    ) -> RecoveryAdvice? {
        let title = advice.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = advice.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionIDs = advice.actions.map(\.id)

        guard title.isEmpty == false,
              title.count <= 80,
              message.isEmpty == false,
              message.count <= 500,
              1...3 ~= actionIDs.count,
              actionIDs.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }),
              Set(actionIDs).count == actionIDs.count else {
            return nil
        }

        let canonicalActions = actionIDs.compactMap { catalog.actionsByID[$0] }
        guard canonicalActions.count == actionIDs.count else {
            return nil
        }

        return RecoveryAdvice(
            title: title,
            message: message,
            actions: canonicalActions
        )
    }
}
