import Foundation
import SwiftMend
import Testing
@testable import SwiftMendEvaluation

struct RecoveryEvaluationTests {
    @Test("The bundled v1 dataset covers every category and split")
    func bundledDatasetCoverage() throws {
        let dataset = try RecoveryEvaluationDataset.bundledV1()

        #expect(dataset.schemaVersion == 1)
        #expect(dataset.datasetVersion == "1.0.0")
        #expect(dataset.scenarios.count == 21)
        #expect(Set(dataset.scenarios.map(\.category)) == Set(RecoveryScenarioCategory.allCases))
        for category in RecoveryScenarioCategory.allCases {
            let categoryScenarios = dataset.scenarios.filter { $0.category == category }
            #expect(Set(categoryScenarios.map(\.split)) == Set(RecoveryEvaluationSplit.allCases))
        }
    }

    @Test("Fine-tuning export uses only the requested split and canonical action IDs")
    func fineTuningExport() throws {
        let dataset = try RecoveryEvaluationDataset.bundledV1()
        let records = try RecoveryFineTuningExporter.records(
            from: dataset,
            split: .training
        )
        let data = try RecoveryFineTuningExporter.jsonLines(
            from: dataset,
            split: .training
        )
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")

        #expect(records.count == 7)
        #expect(lines.count == records.count)
        #expect(Set(records.map(\.scenarioID)).isDisjoint(with: Set(
            dataset.scenarios.filter { $0.split == .test }.map(\.id)
        )))
        for record in records {
            #expect(record.messages.map(\.role) == ["system", "user", "assistant"])
            let scenario = try #require(dataset.scenarios.first { $0.id == record.scenarioID })
            for actionID in scenario.referenceAdvice.actions.map(\.id) {
                #expect(record.messages.last?.content.contains(actionID) == true)
            }
        }
    }

    @Test("Candidate parsing enforces action IDs and canonical developer titles")
    func candidateParsing() throws {
        let approvedActions = [RecoveryAction(id: "retry", title: "Try Again")]
        let candidate = RecoveryEvaluationCandidateParser.parse(
            """
            ```json
            {"title":"Reconnect","message":"Reconnect and retry.","actionIDs":["retry"]}
            ```
            """,
            approvedActions: approvedActions
        )

        #expect(candidate.isValidJSON)
        #expect(candidate.advice?.actions == approvedActions)
        #expect(
            RecoveryEvaluationCandidateParser.parse(
                #"{"title":"Recover","message":"Retry.","actions":["Try Again"]}"#,
                approvedActions: approvedActions
            ).isValidJSON == false
        )
        #expect(
            RecoveryEvaluationCandidateParser.parse(
                #"{"title":"Recover","message":"Retry.","actionIDs":["unknown"]}"#,
                approvedActions: approvedActions
            ).isValidJSON == false
        )
        #expect(
            RecoveryEvaluationCandidateParser.parse(
                #"{"title":"Recover","message":"Retry.","actionIDs":["retry","retry"]}"#,
                approvedActions: approvedActions
            ).isValidJSON == false
        )
    }

    @Test("The runner measures model output, fallback, rule precedence, latency, and memory")
    func runnerMetrics() async throws {
        let provider = ScenarioCandidateProvider()
        let dataset = RecoveryEvaluationDataset(
            schemaVersion: 1,
            datasetVersion: "test",
            scenarios: [
                scenario(id: "model", code: 1),
                scenario(id: "fallback", code: 2),
                scenario(id: "rule", code: 3, rules: [matchingRule])
            ]
        )
        let report = try await RecoveryEvaluationRunner(
            peakMemoryReader: { 4_096 }
        ).evaluate(
            dataset: dataset,
            provider: provider,
            runMetadata: runMetadata()
        )

        #expect(report.metrics.scenarioCount == 3)
        #expect(report.metrics.modelAttemptCount == 2)
        #expect(abs(report.metrics.recoveryAccuracy - (2.0 / 3.0)) < 0.0001)
        #expect(abs(report.metrics.validJSONRate - 0.5) < 0.0001)
        #expect(abs(report.metrics.fallbackFrequency - (1.0 / 3.0)) < 0.0001)
        #expect(report.metrics.meanLatencyMilliseconds >= 0)
        #expect(report.metrics.p95LatencyMilliseconds >= report.metrics.meanLatencyMilliseconds)
        #expect(report.metrics.peakMemoryBytes == 4_096)
        #expect(report.results.last?.source == "developer-rule:known-error")
        #expect(await provider.callCount == 2)
    }

    @Test("The model gate rejects a candidate that loses recovery quality")
    func comparisonGate() async throws {
        let dataset = RecoveryEvaluationDataset(
            schemaVersion: 1,
            datasetVersion: "gate-test",
            scenarios: [scenario(id: "comparison", code: 1)]
        )
        let baseline = try await RecoveryEvaluationRunner(
            peakMemoryReader: { 4_096 }
        ).evaluate(
            dataset: dataset,
            provider: AlwaysValidCandidateProvider(),
            runMetadata: runMetadata(
                parameterCount: 1_000_000_000,
                sha256: String(repeating: "a", count: 64)
            )
        )
        let candidate = try await RecoveryEvaluationRunner(
            peakMemoryReader: { 4_096 }
        ).evaluate(
            dataset: dataset,
            provider: AlwaysInvalidCandidateProvider(),
            runMetadata: runMetadata(
                parameterCount: 270_000_000,
                sha256: String(repeating: "b", count: 64)
            )
        )
        let result = try RecoveryModelComparisonGate.compare(
            baseline: baseline,
            candidate: candidate,
            tolerance: RecoveryModelComparisonTolerance(
                maximumRecoveryAccuracyDrop: 0,
                maximumValidJSONRateDrop: 0,
                maximumFallbackFrequencyIncrease: 0,
                maximumP95LatencyRatio: 1_000_000_000,
                maximumPeakMemoryRatio: 1
            )
        )

        #expect(result.passes == false)
        #expect(result.failures.contains(.recoveryAccuracy))
        #expect(result.failures.contains(.validJSONRate))
        #expect(result.failures.contains(.fallbackFrequency))
    }

    @Test("The model gate rejects wrong model roles and mismatched environments")
    func comparisonIntegrity() async throws {
        let dataset = RecoveryEvaluationDataset(
            schemaVersion: 1,
            datasetVersion: "integrity-test",
            scenarios: [scenario(id: "comparison-integrity", code: 1)]
        )
        let baseline = try await RecoveryEvaluationRunner().evaluate(
            dataset: dataset,
            provider: AlwaysValidCandidateProvider(),
            runMetadata: runMetadata(
                parameterCount: 1_000_000_000,
                sha256: String(repeating: "a", count: 64)
            )
        )
        let wrongRole = try await RecoveryEvaluationRunner().evaluate(
            dataset: dataset,
            provider: AlwaysValidCandidateProvider(),
            runMetadata: runMetadata(
                parameterCount: 1_000_000_000,
                sha256: String(repeating: "b", count: 64)
            )
        )
        let wrongEnvironment = try await RecoveryEvaluationRunner().evaluate(
            dataset: dataset,
            provider: AlwaysValidCandidateProvider(),
            runMetadata: runMetadata(
                parameterCount: 270_000_000,
                sha256: String(repeating: "b", count: 64),
                hardwareModel: "different-hardware"
            )
        )
        let tolerance = RecoveryModelComparisonTolerance(
            maximumRecoveryAccuracyDrop: 0,
            maximumValidJSONRateDrop: 0,
            maximumFallbackFrequencyIncrease: 0,
            maximumP95LatencyRatio: 1,
            maximumPeakMemoryRatio: 1
        )

        #expect(throws: RecoveryModelComparisonError.wrongModelRoles) {
            try RecoveryModelComparisonGate.compare(
                baseline: baseline,
                candidate: wrongRole,
                tolerance: tolerance
            )
        }
        #expect(throws: RecoveryModelComparisonError.environmentMismatch) {
            try RecoveryModelComparisonGate.compare(
                baseline: baseline,
                candidate: wrongEnvironment,
                tolerance: tolerance
            )
        }
    }

    @Test("Report validation rejects metrics that do not match scenario results")
    func reportIntegrity() async throws {
        let dataset = RecoveryEvaluationDataset(
            schemaVersion: 1,
            datasetVersion: "report-integrity-test",
            scenarios: [scenario(id: "report-integrity", code: 1)]
        )
        let report = try await RecoveryEvaluationRunner().evaluate(
            dataset: dataset,
            provider: AlwaysValidCandidateProvider(),
            runMetadata: runMetadata()
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        )
        var metrics = try #require(object["metrics"] as? [String: Any])
        metrics["recoveryAccuracy"] = 0
        object["metrics"] = metrics
        let tampered = try JSONDecoder().decode(
            RecoveryEvaluationReport.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(throws: RecoveryEvaluationReportError.inconsistentMetrics) {
            try tampered.validate()
        }
    }

    private func scenario(
        id: String,
        code: Int,
        rules: [RecoveryRule] = []
    ) -> RecoveryEvaluationScenario {
        RecoveryEvaluationScenario(
            id: id,
            category: .networking,
            split: .test,
            snapshot: ErrorSnapshot(
                domain: "Evaluation",
                code: code,
                message: "Request failed"
            ),
            context: RecoveryContext(feature: "evaluation"),
            rules: rules,
            approvedActions: [retryAction],
            acceptableActionIDSets: [["retry"]],
            referenceAdvice: RecoveryAdvice(
                title: "Try the request again",
                message: "Retry the request to continue.",
                actions: [retryAction]
            ),
            fallbackAdvice: RecoveryAdvice(
                title: "Unavailable",
                message: "Try later.",
                actions: [RecoveryAction(id: "dismiss", title: "Dismiss")]
            )
        )
    }

    private func runMetadata(
        parameterCount: Int64 = 1_000_000_000,
        sha256: String = String(repeating: "a", count: 64),
        hardwareModel: String = "test-hardware"
    ) -> RecoveryEvaluationRunMetadata {
        RecoveryEvaluationRunMetadata(
            model: RecoveryEvaluationModelIdentity(
                id: "test/model-\(parameterCount)",
                revision: "test-revision",
                fileName: "model.litertlm",
                fileSize: 1,
                sha256: sha256,
                parameterCount: parameterCount
            ),
            runtime: "test-runtime",
            backend: "cpu:default",
            hardwareModel: hardwareModel,
            operatingSystem: "test-os"
        )
    }

    private var retryAction: RecoveryAction {
        RecoveryAction(id: "retry", title: "Try Again")
    }

    private var matchingRule: RecoveryRule {
        RecoveryRule(
            id: "known-error",
            matcher: ErrorMatcher(domains: ["Evaluation"], codes: [3]),
            advice: RecoveryAdvice(
                title: "Known recovery",
                message: "Retry this request.",
                actions: [retryAction]
            )
        )
    }
}

private struct AlwaysValidCandidateProvider: RecoveryEvaluationCandidateProviding {
    func candidate(for request: RecoveryModelRequest) async -> RecoveryEvaluationCandidate {
        RecoveryEvaluationCandidate(
            advice: RecoveryAdvice(
                title: "Retry",
                message: "Try the request again.",
                actions: [RecoveryAction(id: "retry", title: "Changed title")]
            ),
            isValidJSON: true
        )
    }
}

private struct AlwaysInvalidCandidateProvider: RecoveryEvaluationCandidateProviding {
    func candidate(for request: RecoveryModelRequest) async -> RecoveryEvaluationCandidate {
        .providerFailure("invalid-json")
    }
}

private actor ScenarioCandidateProvider: RecoveryEvaluationCandidateProviding {
    private(set) var callCount = 0

    func candidate(for request: RecoveryModelRequest) async -> RecoveryEvaluationCandidate {
        callCount += 1
        if request.snapshot.code == 1 {
            return RecoveryEvaluationCandidate(
                advice: RecoveryAdvice(
                    title: "Reconnect",
                    message: "Reconnect and try again.",
                    actions: [RecoveryAction(id: "retry", title: "Changed by model")]
                ),
                isValidJSON: true
            )
        }
        return .providerFailure("invalid-json")
    }
}
