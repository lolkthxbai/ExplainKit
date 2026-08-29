import Foundation
import SwiftMend

public enum RecoveryScenarioCategory: String, CaseIterable, Codable, Sendable {
    case password
    case authentication
    case networking
    case permissions
    case storage
    case payments
    case serviceFailures = "service-failures"
}

public enum RecoveryEvaluationSplit: String, CaseIterable, Codable, Sendable {
    case training
    case validation
    case test
}

public struct RecoveryEvaluationDataset: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetVersion: String
    public let scenarios: [RecoveryEvaluationScenario]

    public init(
        schemaVersion: Int,
        datasetVersion: String,
        scenarios: [RecoveryEvaluationScenario]
    ) {
        self.schemaVersion = schemaVersion
        self.datasetVersion = datasetVersion
        self.scenarios = scenarios
    }

    public static func bundledV1() throws -> RecoveryEvaluationDataset {
        try bundled(version: "v1")
    }

    public static func bundledV2() throws -> RecoveryEvaluationDataset {
        try bundled(version: "v2")
    }

    public static func bundledLatest() throws -> RecoveryEvaluationDataset {
        try bundledV2()
    }

    private static func bundled(version: String) throws -> RecoveryEvaluationDataset {
        guard let url = Bundle.module.url(
            forResource: "recovery-scenarios",
            withExtension: "json",
            subdirectory: "Resources/Datasets/\(version)"
        ) else {
            throw RecoveryEvaluationDatasetError.bundledDatasetMissing
        }
        return try load(from: url)
    }

    public static func load(from url: URL) throws -> RecoveryEvaluationDataset {
        let dataset = try JSONDecoder().decode(
            RecoveryEvaluationDataset.self,
            from: Data(contentsOf: url)
        )
        try dataset.validate()
        return dataset
    }

    public func validate() throws {
        guard schemaVersion == 1,
              datasetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              scenarios.isEmpty == false else {
            throw RecoveryEvaluationDatasetError.invalidMetadata
        }

        guard Set(scenarios.map(\.id)).count == scenarios.count else {
            throw RecoveryEvaluationDatasetError.duplicateScenarioID
        }

        for scenario in scenarios {
            try scenario.validate()
        }
    }
}

public struct RecoveryEvaluationScenario: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: RecoveryScenarioCategory
    public let split: RecoveryEvaluationSplit
    public let snapshot: ErrorSnapshot
    public let context: RecoveryContext
    public let rules: [RecoveryRule]
    public let approvedActions: [RecoveryAction]
    public let acceptableActionIDSets: [[String]]
    public let referenceAdvice: RecoveryAdvice
    public let fallbackAdvice: RecoveryAdvice

    public init(
        id: String,
        category: RecoveryScenarioCategory,
        split: RecoveryEvaluationSplit,
        snapshot: ErrorSnapshot,
        context: RecoveryContext,
        rules: [RecoveryRule] = [],
        approvedActions: [RecoveryAction],
        acceptableActionIDSets: [[String]],
        referenceAdvice: RecoveryAdvice,
        fallbackAdvice: RecoveryAdvice
    ) {
        self.id = id
        self.category = category
        self.split = split
        self.snapshot = snapshot
        self.context = context
        self.rules = rules
        self.approvedActions = approvedActions
        self.acceptableActionIDSets = acceptableActionIDSets
        self.referenceAdvice = referenceAdvice
        self.fallbackAdvice = fallbackAdvice
    }

    fileprivate func validate() throws {
        let scenarioID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scenarioID.isEmpty == false,
              snapshot.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              snapshot.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              context.feature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              approvedActions.isEmpty == false,
              acceptableActionIDSets.isEmpty == false else {
            throw RecoveryEvaluationDatasetError.invalidScenario(id)
        }

        let actionIDs = approvedActions.map(\.id)
        let approvedIDSet = Set(actionIDs)
        guard approvedIDSet.count == actionIDs.count,
              approvedActions.allSatisfy({
                  $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
              }) else {
            throw RecoveryEvaluationDatasetError.invalidActionCatalog(id)
        }

        for acceptableSet in acceptableActionIDSets {
            guard 1...3 ~= acceptableSet.count,
                  Set(acceptableSet).count == acceptableSet.count,
                  acceptableSet.allSatisfy(approvedIDSet.contains) else {
                throw RecoveryEvaluationDatasetError.invalidExpectedActions(id)
            }
        }

        let referenceIDs = referenceAdvice.actions.map(\.id)
        guard referenceAdvice.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              referenceAdvice.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              referenceAdvice.actions.allSatisfy({ catalogAction in
                  approvedActions.contains(where: { $0 == catalogAction })
              }),
              acceptableActionIDSets.contains(where: { Set($0) == Set(referenceIDs) }) else {
            throw RecoveryEvaluationDatasetError.invalidReferenceAdvice(id)
        }
    }
}

public enum RecoveryEvaluationDatasetError: Error, Equatable, Sendable {
    case bundledDatasetMissing
    case invalidMetadata
    case duplicateScenarioID
    case invalidScenario(String)
    case invalidActionCatalog(String)
    case invalidExpectedActions(String)
    case invalidReferenceAdvice(String)
}
