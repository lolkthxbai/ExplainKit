import Foundation
import SwiftMendLiteRT

@main
struct SwiftMendModelTool {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let modelPath = value(after: "--model", in: arguments),
              let modelID = value(after: "--id", in: arguments),
              let revision = value(after: "--revision", in: arguments),
              let parameterCountText = value(after: "--parameter-count", in: arguments),
              let parameterCount = Int64(parameterCountText),
              let outputPath = value(after: "--output", in: arguments) else {
            throw ModelToolError.usage
        }

        let manifest = try LocalGemmaModelManifest.create(
            for: URL(filePath: modelPath),
            id: modelID,
            revision: revision,
            parameterCount: parameterCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputURL = URL(filePath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(manifest).write(to: outputURL, options: .atomic)
        print("Wrote a verified model manifest to \(outputURL.path)")
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

private enum ModelToolError: Error, CustomStringConvertible {
    case usage

    var description: String {
        "Usage: swift run SwiftMendModelTool --model <model.litertlm> --id <model-id> --revision <training-revision> --parameter-count <count> --output <manifest.json>"
    }
}
