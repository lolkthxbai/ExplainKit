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
        maximumRecoveryAccuracyDrop >= 0
            && maximumValidJSONRateDrop >= 0
            && maximumFallbackFrequencyIncrease >= 0
            && maximumP95LatencyRatio > 0
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
        guard baseline.datasetVersion == candidate.datasetVersion,
              Set(baseline.results.map(\.scenarioID)) == Set(candidate.results.map(\.scenarioID)),
              baseline.results.isEmpty == false else {
            throw RecoveryModelComparisonError.incomparableReports
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
        if candidate.metrics.peakMemoryBytes
            > UInt64(Double(baseline.metrics.peakMemoryBytes) * tolerance.maximumPeakMemoryRatio) {
            failures.append(.peakMemory)
        }
        return RecoveryModelComparisonResult(passes: failures.isEmpty, failures: failures)
    }
}

public enum RecoveryModelComparisonError: Error, Equatable, Sendable {
    case invalidTolerance
    case incomparableReports
}
