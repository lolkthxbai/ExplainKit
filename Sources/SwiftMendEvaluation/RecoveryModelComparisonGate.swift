import Foundation

public struct RecoveryModelComparisonTolerance: Equatable, Sendable {
    public let maximumRecoveryAccuracyDrop: Double
    public let maximumValidJSONRateDrop: Double
    public let maximumFallbackFrequencyIncrease: Double
    public let maximumP95LatencyRatio: Double
    public let maximumPeakMemoryRatio: Double

    public init(
        maximumRecoveryAccuracyDrop: Double,
        maximumValidJSONRateDrop: Double,
        maximumFallbackFrequencyIncrease: Double,
        maximumP95LatencyRatio: Double,
        maximumPeakMemoryRatio: Double
    ) {
        self.maximumRecoveryAccuracyDrop = maximumRecoveryAccuracyDrop
        self.maximumValidJSONRateDrop = maximumValidJSONRateDrop
        self.maximumFallbackFrequencyIncrease = maximumFallbackFrequencyIncrease
        self.maximumP95LatencyRatio = maximumP95LatencyRatio
        self.maximumPeakMemoryRatio = maximumPeakMemoryRatio
    }

    fileprivate var isValid: Bool {
        maximumRecoveryAccuracyDrop.isFinite
            && 0...1 ~= maximumRecoveryAccuracyDrop
            && maximumValidJSONRateDrop.isFinite
            && 0...1 ~= maximumValidJSONRateDrop
            && maximumFallbackFrequencyIncrease.isFinite
            && 0...1 ~= maximumFallbackFrequencyIncrease
            && maximumP95LatencyRatio.isFinite
            && maximumP95LatencyRatio > 0
            && maximumPeakMemoryRatio.isFinite
            && maximumPeakMemoryRatio > 0
    }
}

public struct RecoveryModelComparisonResult: Equatable, Sendable {
    public let passes: Bool
    public let failures: [RecoveryModelComparisonFailure]
}

public enum RecoveryModelComparisonFailure: String, Equatable, Sendable {
    case recoveryAccuracy
    case validJSONRate
    case fallbackFrequency
    case p95Latency
    case peakMemory
}

public enum RecoveryModelComparisonGate {
    public static func compare(
        baseline: RecoveryEvaluationReport,
        candidate: RecoveryEvaluationReport,
        tolerance: RecoveryModelComparisonTolerance
    ) throws -> RecoveryModelComparisonResult {
        guard tolerance.isValid else {
            throw RecoveryModelComparisonError.invalidTolerance
        }
        try baseline.validate()
        try candidate.validate()
        guard baseline.datasetVersion == candidate.datasetVersion,
              Set(baseline.results.map(\.scenarioID)) == Set(candidate.results.map(\.scenarioID)),
              baseline.results.isEmpty == false else {
            throw RecoveryModelComparisonError.incomparableReports
        }
        guard baseline.run.model.parameterCount == 1_000_000_000,
              candidate.run.model.parameterCount == 270_000_000 else {
            throw RecoveryModelComparisonError.wrongModelRoles
        }
        guard baseline.run.environmentFingerprint == candidate.run.environmentFingerprint else {
            throw RecoveryModelComparisonError.environmentMismatch
        }
        guard baseline.run.model.sha256 != candidate.run.model.sha256 else {
            throw RecoveryModelComparisonError.identicalArtifacts
        }

        var failures: [RecoveryModelComparisonFailure] = []
        if candidate.metrics.recoveryAccuracy
            < baseline.metrics.recoveryAccuracy - tolerance.maximumRecoveryAccuracyDrop {
            failures.append(.recoveryAccuracy)
        }
        if candidate.metrics.validJSONRate
            < baseline.metrics.validJSONRate - tolerance.maximumValidJSONRateDrop {
            failures.append(.validJSONRate)
        }
        if candidate.metrics.fallbackFrequency
            > baseline.metrics.fallbackFrequency + tolerance.maximumFallbackFrequencyIncrease {
            failures.append(.fallbackFrequency)
        }
        if candidate.metrics.p95LatencyMilliseconds
            > baseline.metrics.p95LatencyMilliseconds * tolerance.maximumP95LatencyRatio {
            failures.append(.p95Latency)
        }
        if Double(candidate.metrics.peakMemoryBytes)
            > Double(baseline.metrics.peakMemoryBytes) * tolerance.maximumPeakMemoryRatio {
            failures.append(.peakMemory)
        }
        return RecoveryModelComparisonResult(passes: failures.isEmpty, failures: failures)
    }
}

public enum RecoveryModelComparisonError: Error, Equatable, Sendable {
    case invalidTolerance
    case incomparableReports
    case wrongModelRoles
    case environmentMismatch
    case identicalArtifacts
}
