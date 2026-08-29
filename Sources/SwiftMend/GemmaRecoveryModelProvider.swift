import Foundation

protocol RecoveryHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: RecoveryHTTPClient {}

/// A hosted Gemma provider backed by the Gemini API `generateContent` endpoint.
public struct GemmaRecoveryModelProvider: RecoveryModelProviding {
    public static let defaultModel = "gemma-4-26b-a4b-it"

    private let apiKey: String
    private let model: String
    private let client: any RecoveryHTTPClient

    public init(apiKey: String, model: String = Self.defaultModel) throws {
        try self.init(apiKey: apiKey, model: model, client: URLSession.shared)
    }

    init(
        apiKey: String,
        model: String = Self.defaultModel,
        client: any RecoveryHTTPClient
    ) throws {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              Self.isValidModelIdentifier(model) else {
            throw GemmaProviderError.invalidConfiguration
        }

        self.apiKey = apiKey
        self.model = model
        self.client = client
    }

    public func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        let catalog: ValidatedRecoveryActionCatalog
        do {
            catalog = try request.validatedActionCatalog()
        } catch {
            throw GemmaProviderError.invalidRequest
        }

        let urlRequest = try makeRequest(request, catalog: catalog)
        let (data, response) = try await client.data(for: urlRequest)

        guard let response = response as? HTTPURLResponse else {
            throw GemmaProviderError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            throw GemmaProviderError.httpStatus(response.statusCode)
        }

        do {
            let response = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
            guard let text = response.candidates
                .first?
                .content
                .parts
                .compactMap(\.text)
                .last else {
                throw GemmaProviderError.invalidResponse
            }
            return try validateAdvice(from: text, catalog: catalog)
        } catch let error as GemmaProviderError {
            throw error
        } catch {
            throw GemmaProviderError.invalidResponse
        }
    }

    private func makeRequest(
        _ request: RecoveryModelRequest,
        catalog: ValidatedRecoveryActionCatalog
    ) throws -> URLRequest {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw GemmaProviderError.invalidConfiguration
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let promptRequest = RecoveryModelRequest(
            snapshot: request.snapshot,
            context: request.context,
            approvedActions: catalog.actions
        )

        let body = GenerateContentRequest(
            systemInstruction: Content(parts: [
                Part(text: RecoveryModelPrompt.systemInstruction)
            ]),
            contents: [
                Content(
                    role: "user",
                    parts: [Part(text: try RecoveryModelPrompt.userPrompt(for: promptRequest))]
                )
            ],
            generationConfig: GenerationConfig(
                temperature: 0,
                candidateCount: 1,
                maxOutputTokens: 512,
                thinkingConfig: ThinkingConfig(thinkingLevel: "minimal")
            )
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
    }

    private func validateAdvice(
        from text: String,
        catalog: ValidatedRecoveryActionCatalog
    ) throws -> RecoveryAdvice {
        guard let data = jsonData(from: text),
              let generated = try? JSONDecoder().decode(GeneratedAdvice.self, from: data) else {
            throw GemmaProviderError.invalidResponse
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
            throw GemmaProviderError.invalidResponse
        }

        let actions = actionIDs.compactMap { catalog.actionsByID[$0] }
        guard actions.count == actionIDs.count else {
            throw GemmaProviderError.invalidResponse
        }

        return RecoveryAdvice(
            title: title,
            message: message,
            actions: actions
        )
    }

    private func jsonData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let json = lines
            .dropFirst()
            .dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return json.data(using: .utf8)
    }

    private static func isValidModelIdentifier(_ model: String) -> Bool {
        model.isEmpty == false && model.utf8.allSatisfy { byte in
            (65...90).contains(byte)
                || (97...122).contains(byte)
                || (48...57).contains(byte)
                || [45, 46, 95].contains(byte)
        }
    }
}

public enum GemmaProviderError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
}

private struct GenerateContentRequest: Encodable {
    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct Content: Codable {
    let role: String?
    let parts: [Part]

    init(role: String? = nil, parts: [Part]) {
        self.role = role
        self.parts = parts
    }
}

private struct Part: Codable {
    let text: String?

    init(text: String) {
        self.text = text
    }
}

private struct GenerationConfig: Encodable {
    let temperature: Double
    let candidateCount: Int
    let maxOutputTokens: Int
    let thinkingConfig: ThinkingConfig
}

private struct ThinkingConfig: Encodable {
    let thinkingLevel: String
}

private struct GenerateContentResponse: Decodable {
    let candidates: [Candidate]
}

private struct Candidate: Decodable {
    let content: Content
}

private struct GeneratedAdvice: Decodable {
    let title: String
    let message: String
    let actionIDs: [String]
}
