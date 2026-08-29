import Foundation
import SwiftMend

public struct RecoveryEvaluationCandidate: Equatable, Sendable {
    public let advice: RecoveryAdvice?
    public let isValidJSON: Bool
    public let failureDescription: String?

    public init(
        advice: RecoveryAdvice?,
        isValidJSON: Bool,
        failureDescription: String? = nil
    ) {
        self.advice = advice
        self.isValidJSON = isValidJSON
        self.failureDescription = failureDescription
    }

    public static func providerFailure(_ description: String) -> RecoveryEvaluationCandidate {
        RecoveryEvaluationCandidate(
            advice: nil,
            isValidJSON: false,
            failureDescription: description
        )
    }
}

public protocol RecoveryEvaluationCandidateProviding: Sendable {
    func candidate(for request: RecoveryModelRequest) async -> RecoveryEvaluationCandidate
}

public enum RecoveryEvaluationCandidateParser {
    public static func parse(
        _ response: String,
        approvedActions: [RecoveryAction]
    ) -> RecoveryEvaluationCandidate {
        guard let data = jsonData(from: response),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .providerFailure("invalid-json")
        }

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = payload.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionIDs = payload.actionIDs
        var catalog: [String: RecoveryAction] = [:]
        for action in approvedActions {
            guard action.id.isEmpty == false,
                  action.title.isEmpty == false,
                  catalog[action.id] == nil else {
                return .providerFailure("invalid-action-catalog")
            }
            catalog[action.id] = action
        }
        guard title.isEmpty == false,
              title.count <= 80,
              message.isEmpty == false,
              message.count <= 500,
              1...3 ~= actionIDs.count,
              Set(actionIDs).count == actionIDs.count,
              actionIDs.allSatisfy({ catalog[$0] != nil }) else {
            return .providerFailure("invalid-structured-response")
        }

        return RecoveryEvaluationCandidate(
            advice: RecoveryAdvice(
                title: title,
                message: message,
                actions: actionIDs.compactMap { catalog[$0] }
            ),
            isValidJSON: true
        )
    }

    private static func jsonData(from response: String) -> Data? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed.data(using: .utf8)
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3,
              let openingFence = lines.first,
              openingFence == "```" || openingFence.lowercased() == "```json",
              lines.last == "```" else {
            return nil
        }
        return lines.dropFirst().dropLast().joined(separator: "\n").data(using: .utf8)
    }
}

private struct Payload: Decodable {
    let title: String
    let message: String
    let actionIDs: [String]
}
