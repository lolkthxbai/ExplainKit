import Darwin
import Foundation
import SwiftMendEvaluation

@main
struct SwiftMendCompare {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let parsed = try ComparisonArguments.parse(arguments)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let baseline = try decoder.decode(
            RecoveryEvaluationReport.self,
            from: Data(contentsOf: parsed.baselineURL)
        )
        let candidate = try decoder.decode(
            RecoveryEvaluationReport.self,
            from: Data(contentsOf: parsed.candidateURL)
        )
        let result = try RecoveryModelComparisonGate.compare(
            baseline: baseline,
            candidate: candidate,
            tolerance: parsed.tolerance
        )

        if result.passes {
            print("PASS: the candidate is within the explicitly supplied tolerance.")
        } else {
            print("FAIL: \(result.failures.map(\.rawValue).joined(separator: ", "))")
            exit(EXIT_FAILURE)
        }
    }
}

private struct ComparisonArguments {
    let baselineURL: URL
    let candidateURL: URL
    let tolerance: RecoveryModelComparisonTolerance

    static func parse(_ arguments: [String]) throws -> ComparisonArguments {
        guard let baseline = value(after: "--baseline", in: arguments),
              let candidate = value(after: "--candidate", in: arguments),
              let accuracyDrop = number(after: "--max-accuracy-drop", in: arguments),
              let jsonDrop = number(after: "--max-json-drop", in: arguments),
              let fallbackIncrease = number(after: "--max-fallback-increase", in: arguments),
              let latencyRatio = number(after: "--max-latency-ratio", in: arguments),
              let memoryRatio = number(after: "--max-memory-ratio", in: arguments) else {
            throw ComparisonArgumentError.usage
        }
        return ComparisonArguments(
            baselineURL: URL(filePath: baseline),
            candidateURL: URL(filePath: candidate),
            tolerance: RecoveryModelComparisonTolerance(
                maximumRecoveryAccuracyDrop: accuracyDrop,
                maximumValidJSONRateDrop: jsonDrop,
                maximumFallbackFrequencyIncrease: fallbackIncrease,
                maximumP95LatencyRatio: latencyRatio,
                maximumPeakMemoryRatio: memoryRatio
            )
        )
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func number(after option: String, in arguments: [String]) -> Double? {
        value(after: option, in: arguments).flatMap(Double.init)
    }
}

private enum ComparisonArgumentError: Error, CustomStringConvertible {
    case usage

    var description: String {
        "Usage: swift run SwiftMendCompare --baseline <1b-report.json> --candidate <270m-report.json> --max-accuracy-drop <fraction> --max-json-drop <fraction> --max-fallback-increase <fraction> --max-latency-ratio <ratio> --max-memory-ratio <ratio>"
    }
}
