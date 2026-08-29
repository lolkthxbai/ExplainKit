import Darwin
import Foundation
import SwiftMend
import SwiftMendEvaluation
import SwiftMendLiteRT

@main
struct SwiftMendBenchmark {
    static func main() async throws {
        let arguments = try BenchmarkArguments.parse(CommandLine.arguments)
        let dataset = if let datasetURL = arguments.datasetURL {
            try RecoveryEvaluationDataset.load(from: datasetURL)
        } else {
            try RecoveryEvaluationDataset.bundledV1()
        }

        let configuration = LocalGemmaConfiguration(
            modelURL: arguments.modelURL,
            backend: arguments.backend,
            cacheURL: arguments.cacheURL
        )
        let localProvider = try await LocalGemmaRecoveryModelProvider.load(
            configuration: configuration
        )
        let report = try await RecoveryEvaluationRunner(
            peakMemoryReader: ProcessPeakMemory.read
        ).evaluate(
            dataset: dataset,
            provider: LocalCandidateProvider(provider: localProvider),
            split: arguments.split
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(
            at: arguments.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: arguments.outputURL, options: .atomic)

        print("Dataset: \(report.datasetVersion)")
        print("Scenarios: \(report.metrics.scenarioCount)")
        print("Recovery accuracy: \(Self.percent(report.metrics.recoveryAccuracy))")
        print("Valid JSON rate: \(Self.percent(report.metrics.validJSONRate))")
        print("Mean latency: \(String(format: "%.1f", report.metrics.meanLatencyMilliseconds)) ms")
        print("P95 latency: \(String(format: "%.1f", report.metrics.p95LatencyMilliseconds)) ms")
        print("Peak memory: \(Self.megabytes(report.metrics.peakMemoryBytes)) MB")
        print("Fallback frequency: \(Self.percent(report.metrics.fallbackFrequency))")
        print("Report: \(arguments.outputURL.path)")
    }

    private static func percent(_ rate: Double) -> String {
        String(format: "%.1f%%", rate * 100)
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}

private struct LocalCandidateProvider: RecoveryEvaluationCandidateProviding {
    let provider: LocalGemmaRecoveryModelProvider

    func candidate(for request: RecoveryModelRequest) async -> RecoveryEvaluationCandidate {
        do {
            let rawResponse = try await provider.rawResponse(for: request)
            return RecoveryEvaluationCandidateParser.parse(
                rawResponse,
                approvedActions: request.approvedActions
            )
        } catch let error as LocalGemmaProviderError {
            return .providerFailure(String(describing: error))
        } catch is CancellationError {
            return .providerFailure("cancelled")
        } catch {
            return .providerFailure("local-provider-error")
        }
    }
}

private enum ProcessPeakMemory {
    static func read() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }
}

private struct BenchmarkArguments {
    let modelURL: URL
    let datasetURL: URL?
    let outputURL: URL
    let cacheURL: URL
    let backend: LocalGemmaBackend
    let split: RecoveryEvaluationSplit?

    static func parse(_ arguments: [String]) throws -> BenchmarkArguments {
        let values = Array(arguments.dropFirst())
        guard let modelPath = value(after: "--model", in: values),
              let outputPath = value(after: "--output", in: values) else {
            throw BenchmarkArgumentError.usage
        }

        let backend: LocalGemmaBackend
        switch value(after: "--backend", in: values) ?? "gpu" {
        case "gpu": backend = .gpu
        case "cpu": backend = .cpu()
        default: throw BenchmarkArgumentError.invalidBackend
        }

        let split: RecoveryEvaluationSplit?
        if let splitValue = value(after: "--split", in: values), splitValue != "all" {
            guard let parsedSplit = RecoveryEvaluationSplit(rawValue: splitValue) else {
                throw BenchmarkArgumentError.invalidSplit
            }
            split = parsedSplit
        } else {
            split = nil
        }

        let cachePath = value(after: "--cache", in: values)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "SwiftMend/LiteRT", directoryHint: .isDirectory).path
        return BenchmarkArguments(
            modelURL: URL(filePath: modelPath),
            datasetURL: value(after: "--dataset", in: values).map { URL(filePath: $0) },
            outputURL: URL(filePath: outputPath),
            cacheURL: URL(filePath: cachePath),
            backend: backend,
            split: split
        )
    }

    private static func value(after option: String, in values: [String]) -> String? {
        guard let index = values.firstIndex(of: option), values.indices.contains(index + 1) else {
            return nil
        }
        return values[index + 1]
    }
}

private enum BenchmarkArgumentError: Error, CustomStringConvertible {
    case usage
    case invalidBackend
    case invalidSplit

    var description: String {
        switch self {
        case .usage:
            "Usage: swift run SwiftMendBenchmark --model <gemma3-1b-it-int4.litertlm> --output <report.json> [--dataset <dataset.json>] [--split training|validation|test|all] [--backend gpu|cpu] [--cache <directory>]"
        case .invalidBackend:
            "Backend must be gpu or cpu."
        case .invalidSplit:
            "Split must be training, validation, test, or all."
        }
    }
}
