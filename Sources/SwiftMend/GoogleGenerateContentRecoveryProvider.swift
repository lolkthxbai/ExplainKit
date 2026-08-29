import Foundation

protocol RecoveryHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: RecoveryHTTPClient {}

enum GoogleModelFamily: String, Sendable {
    case gemini
    case gemma

    func accepts(_ model: String) -> Bool {
        let prefix = rawValue + "-"
        return model.hasPrefix(prefix)
            && model.count > prefix.count
            && model.utf8.allSatisfy { byte in
                (65...90).contains(byte)
                    || (97...122).contains(byte)
                    || (48...57).contains(byte)
                    || [45, 46, 95].contains(byte)
            }
    }
}

enum GoogleGenerateContentError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidRequest
    case invalidResponse
    case httpStatus(Int)
}

struct GoogleGenerationOptions: Sendable {
    let temperature: Double?
    let candidateCount: Int?
    let maxOutputTokens: Int
    let thinkingLevel: String
    let usesStructuredOutput: Bool

    static let gemma = GoogleGenerationOptions(
        temperature: 0,
        candidateCount: 1,
        maxOutputTokens: 512,
        thinkingLevel: "minimal",
        usesStructuredOutput: false
    )

    static let gemini = GoogleGenerationOptions(
        temperature: nil,
        candidateCount: nil,
        maxOutputTokens: 512,
        thinkingLevel: "low",
        usesStructuredOutput: true
    )
}

struct GoogleGenerateContentRecoveryProvider: Sendable {
    private let apiKey: String
    private let model: String
    private let client: any RecoveryHTTPClient
    private let options: GoogleGenerationOptions

    init(
        apiKey: String,
        model: String,
        family: GoogleModelFamily,
        options: GoogleGenerationOptions,
        client: any RecoveryHTTPClient
    ) throws {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              family.accepts(model) else {
            throw GoogleGenerateContentError.invalidConfiguration
        }

        self.apiKey = apiKey
        self.model = model
        self.client = client
        self.options = options
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        let catalog: ValidatedRecoveryActionCatalog
        do {
            catalog = try request.validatedActionCatalog()
        } catch {
            throw GoogleGenerateContentError.invalidRequest
        }

        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(request, catalog: catalog)
        } catch let error as GoogleGenerateContentError {
            throw error
        } catch {
            throw GoogleGenerateContentError.invalidRequest
        }

        let (data, response) = try await client.data(for: urlRequest)

        guard let response = response as? HTTPURLResponse else {
            throw GoogleGenerateContentError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            throw GoogleGenerateContentError.httpStatus(response.statusCode)
        }

        let responseBody: GoogleGenerateContentResponse
        do {
            responseBody = try JSONDecoder().decode(GoogleGenerateContentResponse.self, from: data)
        } catch {
            throw GoogleGenerateContentError.invalidResponse
        }

        guard let text = responseBody.candidates
            .first?
            .content
            .parts
            .compactMap(\.text)
            .last else {
            throw GoogleGenerateContentError.invalidResponse
        }

        return try GoogleGeneratedAdviceDecoder.decode(text, catalog: catalog)
    }

    private func makeRequest(
        _ request: RecoveryModelRequest,
        catalog: ValidatedRecoveryActionCatalog
    ) throws -> URLRequest {
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else {
            throw GoogleGenerateContentError.invalidConfiguration
        }

        let promptRequest = RecoveryModelRequest(
            snapshot: request.snapshot,
            context: request.context,
            approvedActions: catalog.actions
        )
        let schema = options.usesStructuredOutput
            ? GoogleRecoveryAdviceSchema(actionIDs: catalog.actions.map(\.id))
            : nil
        let body = GoogleGenerateContentRequest(
            systemInstruction: GoogleContent(parts: [
                GooglePart(text: RecoveryModelPrompt.systemInstruction)
            ]),
            contents: [
                GoogleContent(
                    role: "user",
                    parts: [GooglePart(text: try RecoveryModelPrompt.userPrompt(for: promptRequest))]
                )
            ],
            generationConfig: GoogleGenerationConfig(
                temperature: options.temperature,
                candidateCount: options.candidateCount,
                maxOutputTokens: options.maxOutputTokens,
                thinkingConfig: GoogleThinkingConfig(thinkingLevel: options.thinkingLevel),
                responseMimeType: options.usesStructuredOutput ? "application/json" : nil,
                responseJsonSchema: schema
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
    }
}

private enum GoogleGeneratedAdviceDecoder {
    static func decode(
        _ text: String,
        catalog: ValidatedRecoveryActionCatalog
    ) throws -> RecoveryAdvice {
        guard let data = jsonData(from: text),
              let generated = try? JSONDecoder().decode(GoogleGeneratedAdvice.self, from: data) else {
            throw GoogleGenerateContentError.invalidResponse
        }

        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = generated.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionIDs = generated.actionIDs

        guard title.isEmpty == false,
              title.count <= 80,
              message.isEmpty == false,
              message.count <= 500,
              1...3 ~= actionIDs.count,
              actionIDs.allSatisfy({
                  $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
              }),
              Set(actionIDs).count == actionIDs.count else {
            throw GoogleGenerateContentError.invalidResponse
        }

        let actions = actionIDs.compactMap { catalog.actionsByID[$0] }
        guard actions.count == actionIDs.count else {
            throw GoogleGenerateContentError.invalidResponse
        }

        return RecoveryAdvice(
            title: title,
            message: message,
            actions: actions
        )
    }

    private static func jsonData(from text: String) -> Data? {
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
}

private struct GoogleGenerateContentRequest: Encodable {
    let systemInstruction: GoogleContent
    let contents: [GoogleContent]
    let generationConfig: GoogleGenerationConfig
}

private struct GoogleContent: Codable {
    let role: String?
    let parts: [GooglePart]

    init(role: String? = nil, parts: [GooglePart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GooglePart: Codable {
    let text: String?

    init(text: String) {
        self.text = text
    }
}

private struct GoogleGenerationConfig: Encodable {
    let temperature: Double?
    let candidateCount: Int?
    let maxOutputTokens: Int
    let thinkingConfig: GoogleThinkingConfig
    let responseMimeType: String?
    let responseJsonSchema: GoogleRecoveryAdviceSchema?
}

private struct GoogleThinkingConfig: Encodable {
    let thinkingLevel: String
}

private struct GoogleRecoveryAdviceSchema: Encodable {
    let type = "OBJECT"
    let properties: Properties
    let required = ["title", "message", "actionIDs"]

    init(actionIDs: [String]) {
        properties = Properties(actionIDs: ActionIDsSchema(allowedIDs: actionIDs))
    }

    struct Properties: Encodable {
        let title = StringSchema()
        let message = StringSchema()
        let actionIDs: ActionIDsSchema
    }

    struct StringSchema: Encodable {
        let type = "STRING"
    }

    struct ActionIDsSchema: Encodable {
        let type = "ARRAY"
        let items: ActionIDSchema
        let minItems = 1
        let maxItems = 3

        init(allowedIDs: [String]) {
            items = ActionIDSchema(allowedIDs: allowedIDs)
        }
    }

    struct ActionIDSchema: Encodable {
        let type = "STRING"
        let allowedIDs: [String]

        enum CodingKeys: String, CodingKey {
            case type
            case allowedIDs = "enum"
        }

        init(allowedIDs: [String]) {
            self.allowedIDs = allowedIDs
        }
    }
}

private struct GoogleGenerateContentResponse: Decodable {
    let candidates: [GoogleCandidate]
}

private struct GoogleCandidate: Decodable {
    let content: GoogleContent
}

private struct GoogleGeneratedAdvice: Decodable {
    let title: String
    let message: String
    let actionIDs: [String]
}
