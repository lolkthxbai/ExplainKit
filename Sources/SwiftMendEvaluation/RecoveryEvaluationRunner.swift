import Foundation
import SwiftMend

public struct RecoveryEvaluationRunner: Sendable {
    private let peakMemoryReader: @Sendable () -> UInt64

    public init(peakMemoryReader: @escaping @Sendable () -> UInt64 = { 0 }) {
        self.peakMemoryReader = peakMemoryReader
    }

    public func evaluate(
        dataset: RecoveryEvaluationDataset,
        provider: any RecoveryEvaluationCandidateProviding,
        runMetadata: RecoveryEvaluationRunMetadata,
        split: RecoveryEvaluationSplit? = nil
    ) async throws -> RecoveryEvaluationReport {
        try dataset.validate()
        try runMetadata.validate()
        let scenarios = dataset.scenarios.filter { split == nil || $0.split == split }
        var results: [RecoveryEvaluationScenarioResult] = []
        results.reserveCapacity(scenarios.count)

        for scenario in scenarios {
            let matchingRule = scenario.rules.first {
                $0.matches(scenario.snapshot, context: scenario.context)
            }
            let candidate: RecoveryEvaluationCandidate?
            let latencyMilliseconds: Double

            if matchingRule == nil {
                let clock = ContinuousClock()
                let start = clock.now
                candidate = await provider.candidate(
                    for: RecoveryModelRequest(
                        snapshot: scenario.snapshot,
                        context: scenario.context,
                        approvedActions: scenario.approvedActions
                    )
                )
                latencyMilliseconds = Self.milliseconds(from: start.duration(to: clock.now))
            } else {
                candidate = nil
                latencyMilliseconds = 0
            }

            let engine = RecoveryEngine(
                rules: scenario.rules,
                fallbackAdvice: scenario.fallbackAdvice,
                approvedModelActions: scenario.approvedActions,
                modelProvider: candidate.map(RecordedCandidateProvider.init)
            )
            let resolution = await engine.resolve(
                scenario.snapshot,
                context: scenario.context
            )
            let selectedIDs = resolution.advice.actions.map(\.id)
            let selectedIDSet = Set(selectedIDs)
            let isAccurate = selectedIDs.isEmpty == false
                && scenario.acceptableActionIDSets.contains { Set($0) == selectedIDSet }

            results.append(
                RecoveryEvaluationScenarioResult(
                    scenarioID: scenario.id,
                    category: scenario.category,
                    split: scenario.split,
                    source: Self.label(for: resolution.source),
                    selectedActionIDs: selectedIDs,
                    isRecoveryAccurate: isAccurate,
                    isValidJSON: candidate?.isValidJSON,
                    latencyMilliseconds: latencyMilliseconds,
                    peakMemoryBytes: peakMemoryReader(),
                    failureDescription: candidate?.failureDescription
                )
            )
        }

        return RecoveryEvaluationReport(
            schemaVersion: 2,
            datasetVersion: dataset.datasetVersion,
            generatedAt: Date(),
            run: runMetadata,
            results: results,
            metrics: RecoveryEvaluationMetrics(results: results)
        )
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func label(for source: RecoveryAdviceSource) -> String {
        switch source {
        case .developerRule(let id): "developer-rule:\(id)"
        case .model: "model"
        case .fallback: "fallback"
        }
    }
}

public struct RecoveryEvaluationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetVersion: String
    public let generatedAt: Date
    public let run: RecoveryEvaluationRunMetadata
    public let results: [RecoveryEvaluationScenarioResult]
    public let metrics: RecoveryEvaluationMetrics

    public func validate() throws {
        try run.validate()
        guard schemaVersion == 2,
              datasetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              results.isEmpty == false,
              Set(results.map(\.scenarioID)).count == results.count else {
            throw RecoveryEvaluationReportError.invalidReport
        }
        for result in results {
            guard result.scenarioID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  result.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  Set(result.selectedActionIDs).count == result.selectedActionIDs.count,
                  result.latencyMilliseconds.isFinite,
                  result.latencyMilliseconds >= 0 else {
                throw RecoveryEvaluationReportError.invalidReport
            }
        }
        guard metrics == RecoveryEvaluationMetrics(results: results) else {
            throw RecoveryEvaluationReportError.inconsistentMetrics
        }
    }
}

public enum RecoveryEvaluationReportError: Error, Equatable, Sendable {
    case invalidReport
    case inconsistentMetrics
}

public struct RecoveryEvaluationScenarioResult: Codable, Equatable, Sendable {
    public let scenarioID: String
    public let category: RecoveryScenarioCategory
    public let split: RecoveryEvaluationSplit
    public let source: String
    public let selectedActionIDs: [String]
    public let isRecoveryAccurate: Bool
    public let isValidJSON: Bool?
    public let latencyMilliseconds: Double
    public let peakMemoryBytes: UInt64
    public let failureDescription: String?
}

public struct RecoveryEvaluationMetrics: Codable, Equatable, Sendable {
    public let scenarioCount: Int
    public let modelAttemptCount: Int
    public let recoveryAccuracy: Double
    public let validJSONRate: Double
    public let meanLatencyMilliseconds: Double
    public let p95LatencyMilliseconds: Double
    public let peakMemoryBytes: UInt64
    public let fallbackFrequency: Double

    fileprivate init(results: [RecoveryEvaluationScenarioResult]) {
        scenarioCount = results.count
        modelAttemptCount = results.count { $0.isValidJSON != nil }
        recoveryAccuracy = Self.rate(results.count { $0.isRecoveryAccurate }, over: results.count)
        validJSONRate = Self.rate(
            results.count { $0.isValidJSON == true },
            over: modelAttemptCount
        )
        let latencies = results.filter { $0.isValidJSON != nil }.map(\.latencyMilliseconds).sorted()
        meanLatencyMilliseconds = latencies.isEmpty
            ? 0
            : latencies.reduce(0, +) / Double(latencies.count)
        if latencies.isEmpty {
            p95LatencyMilliseconds = 0
        } else {
            let index = Int(ceil(Double(latencies.count) * 0.95)) - 1
            p95LatencyMilliseconds = latencies[max(0, index)]
        }
        peakMemoryBytes = results.map(\.peakMemoryBytes).max() ?? 0
        fallbackFrequency = Self.rate(
            results.count { $0.source == "fallback" },
            over: results.count
        )
    }

    private static func rate(_ numerator: Int, over denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

private struct RecordedCandidateProvider: RecoveryModelProviding {
    let candidate: RecoveryEvaluationCandidate

    init(_ candidate: RecoveryEvaluationCandidate) {
        self.candidate = candidate
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        guard let advice = candidate.advice else {
            throw RecordedCandidateError.noValidAdvice
        }
        return advice
    }
}

private enum RecordedCandidateError: Error {
    case noValidAdvice
}
