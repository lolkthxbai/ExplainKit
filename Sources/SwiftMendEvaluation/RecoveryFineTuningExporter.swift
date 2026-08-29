import Foundation
import SwiftMend

public enum RecoveryFineTuningExporter {
    public static func records(
        from dataset: RecoveryEvaluationDataset,
        split: RecoveryEvaluationSplit
    ) throws -> [RecoveryFineTuningRecord] {
        try dataset.validate()
        return try dataset.scenarios
            .filter { $0.split == split }
            .map(makeRecord)
    }

    public static func jsonLines(
        from dataset: RecoveryEvaluationDataset,
        split: RecoveryEvaluationSplit
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records(from: dataset, split: split).map {
            guard let line = String(data: try encoder.encode($0), encoding: .utf8) else {
                throw RecoveryFineTuningExportError.encodingFailed
            }
            return line
        }
        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
            throw RecoveryFineTuningExportError.encodingFailed
        }
        return data
    }

    private static func makeRecord(
        _ scenario: RecoveryEvaluationScenario
    ) throws -> RecoveryFineTuningRecord {
        let response = ReferenceResponse(
            title: scenario.referenceAdvice.title,
            message: scenario.referenceAdvice.message,
            actionIDs: scenario.referenceAdvice.actions.map(\.id)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let responseJSON = String(data: try encoder.encode(response), encoding: .utf8) else {
            throw RecoveryFineTuningExportError.encodingFailed
        }
        let request = RecoveryModelRequest(
            snapshot: scenario.snapshot,
            context: scenario.context,
            approvedActions: scenario.approvedActions
        )

        return RecoveryFineTuningRecord(
            scenarioID: scenario.id,
            category: scenario.category,
            messages: [
                RecoveryFineTuningMessage(
                    role: "system",
                    content: RecoveryModelPrompt.systemInstruction
                ),
                RecoveryFineTuningMessage(
                    role: "user",
                    content: try RecoveryModelPrompt.userPrompt(for: request)
                ),
                RecoveryFineTuningMessage(role: "assistant", content: responseJSON)
            ]
        )
    }
}

public struct RecoveryFineTuningRecord: Codable, Equatable, Sendable {
    public let scenarioID: String
    public let category: RecoveryScenarioCategory
    public let messages: [RecoveryFineTuningMessage]
}

public struct RecoveryFineTuningMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum RecoveryFineTuningExportError: Error, Equatable, Sendable {
    case encodingFailed
}

private struct ReferenceResponse: Encodable {
    let title: String
    let message: String
    let actionIDs: [String]
}
