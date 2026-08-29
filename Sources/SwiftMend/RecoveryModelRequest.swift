import Foundation

/// The privacy-reviewed diagnostic and recovery choices supplied to a model provider.
public struct RecoveryModelRequest: Equatable, Sendable {
    public let snapshot: ErrorSnapshot
    public let context: RecoveryContext
    public let approvedActions: [RecoveryAction]

    public init(
        snapshot: ErrorSnapshot,
        context: RecoveryContext,
        approvedActions: [RecoveryAction]
    ) {
        self.snapshot = snapshot
        self.context = context
        self.approvedActions = approvedActions
    }
}

struct ValidatedRecoveryActionCatalog: Sendable {
    let actions: [RecoveryAction]
    let actionsByID: [String: RecoveryAction]
}

extension RecoveryModelRequest {
    func validatedActionCatalog() throws -> ValidatedRecoveryActionCatalog {
        guard approvedActions.isEmpty == false else {
            throw RecoveryModelRequestValidationError.invalidApprovedActions
        }

        var actionsByID: [String: RecoveryAction] = [:]
        for action in approvedActions {
            guard action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  actionsByID[action.id] == nil else {
                throw RecoveryModelRequestValidationError.invalidApprovedActions
            }
            actionsByID[action.id] = action
        }

        return ValidatedRecoveryActionCatalog(
            actions: approvedActions,
            actionsByID: actionsByID
        )
    }
}

enum RecoveryModelRequestValidationError: Error {
    case invalidApprovedActions
}
