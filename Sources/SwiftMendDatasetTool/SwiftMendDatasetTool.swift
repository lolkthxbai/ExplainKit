import Foundation
import SwiftMendEvaluation

@main
struct SwiftMendDatasetTool {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let outputPath = value(after: "--output", in: arguments),
              let splitValue = value(after: "--split", in: arguments),
              let split = RecoveryEvaluationSplit(rawValue: splitValue),
              split != .test else {
            throw DatasetToolError.usage
        }
        let dataset = if let datasetPath = value(after: "--dataset", in: arguments) {
            try RecoveryEvaluationDataset.load(from: URL(filePath: datasetPath))
        } else {
            try RecoveryEvaluationDataset.bundledLatest()
        }
        let outputURL = URL(filePath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try RecoveryFineTuningExporter.jsonLines(
            from: dataset,
            split: split
        )
        try data.write(to: outputURL, options: .atomic)
        print("Exported \(split.rawValue) records to \(outputURL.path)")
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

private enum DatasetToolError: Error, CustomStringConvertible {
    case usage

    var description: String {
        "Usage: swift run SwiftMendDatasetTool --split training|validation --output <records.jsonl> [--dataset <dataset.json>]"
    }
}
