import Foundation
import SwiftMend

public actor LocalGemmaRecoveryModelProvider: RecoveryModelProviding {
    private let generator: any LocalGemmaTextGenerating

    public static func load(
        configuration: LocalGemmaConfiguration
    ) async throws -> LocalGemmaRecoveryModelProvider {
        let generator = try await LiteRTGemmaTextGenerator.load(configuration: configuration)
        return LocalGemmaRecoveryModelProvider(generator: generator)
    }

    init(generator: any LocalGemmaTextGenerating) {
        self.generator = generator
    }

    public func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        let response = try await rawResponse(for: request)
        let catalog = try validateCatalog(request.approvedActions)
        return try decodeAdvice(response, catalog: catalog)
    }

    /// Generates the model's untrusted response for offline evaluation tooling.
    public func rawResponse(for request: RecoveryModelRequest) async throws -> String {
        _ = try validateCatalog(request.approvedActions)
        let generationRequest = try makeGenerationRequest(request)
        let response = try await generator.generate(generationRequest)
        try Task.checkCancellation()
        return response
    }

    private func validateCatalog(
        _ actions: [RecoveryAction]
    ) throws -> [String: RecoveryAction] {
        guard actions.isEmpty == false else {
            throw LocalGemmaProviderError.invalidRequest
        }

        var catalog: [String: RecoveryAction] = [:]
        for action in actions {
            guard action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  catalog[action.id] == nil else {
                throw LocalGemmaProviderError.invalidRequest
            }
            catalog[action.id] = action
        }
        return catalog
    }

    private func makeGenerationRequest(
        _ request: RecoveryModelRequest
    ) throws -> LocalGemmaGenerationRequest {
        return LocalGemmaGenerationRequest(
            systemInstruction: RecoveryModelPrompt.systemInstruction,
            prompt: try RecoveryModelPrompt.userPrompt(for: request),
            approvedActionIDs: request.approvedActions.map(\.id),
            maximumOutputTokens: 256
        )
    }

    private func decodeAdvice(
        _ response: String,
        catalog: [String: RecoveryAction]
    ) throws -> RecoveryAdvice {
        guard let data = jsonData(from: response),
              let generated = try? JSONDecoder().decode(GeneratedAdvice.self, from: data) else {
            throw LocalGemmaProviderError.invalidResponse
        }

        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = generated.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionIDs = generated.actionIDs

        guard title.isEmpty == false,
              title.count <= 80,
              message.isEmpty == false,
              message.count <= 500,
              1...3 ~= actionIDs.count,
              actionIDs.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }),
              Set(actionIDs).count == actionIDs.count else {
            throw LocalGemmaProviderError.invalidResponse
        }

        let actions = actionIDs.compactMap { catalog[$0] }
        guard actions.count == actionIDs.count else {
            throw LocalGemmaProviderError.invalidResponse
        }

        return RecoveryAdvice(title: title, message: message, actions: actions)
    }

    private func jsonData(from response: String) -> Data? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else {
            return trimmed.data(using: .utf8)
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3,
              let openingFence = lines.first,
              openingFence == "```" || openingFence.lowercased() == "```json",
              lines.last == "```" else {
            return nil
        }

        return lines
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .data(using: .utf8)
    }
}

struct LocalGemmaGenerationRequest: Equatable, Sendable {
    let systemInstruction: String
    let prompt: String
    let approvedActionIDs: [String]
    let maximumOutputTokens: Int
}

protocol LocalGemmaTextGenerating: Sendable {
    func generate(_ request: LocalGemmaGenerationRequest) async throws -> String
}

private struct GeneratedAdvice: Decodable {
    let title: String
    let message: String
    let actionIDs: [String]
}
