import CLiteRTLM
import CryptoKit
import Dispatch
import Foundation

final class LiteRTGemmaTextGenerator: @unchecked Sendable, LocalGemmaTextGenerating {
    private let engine: LiteRTEngineHandle
    private let maximumOutputTokens: Int
    private let queue: DispatchQueue

    private init(
        engine: LiteRTEngineHandle,
        maximumOutputTokens: Int,
        queue: DispatchQueue
    ) {
        self.engine = engine
        self.maximumOutputTokens = maximumOutputTokens
        self.queue = queue
    }

    static func load(configuration: LocalGemmaConfiguration) async throws -> LiteRTGemmaTextGenerator {
        try Task.checkCancellation()
        let queue = DispatchQueue(
            label: "com.lolkthxbai.SwiftMend.LiteRTGemma",
            qos: .userInitiated
        )
        let loaded = try await perform(on: queue) {
            try loadRuntime(configuration: configuration)
        }
        try Task.checkCancellation()
        return LiteRTGemmaTextGenerator(
            engine: loaded.engine,
            maximumOutputTokens: loaded.maximumOutputTokens,
            queue: queue
        )
    }

    func generate(_ request: LocalGemmaGenerationRequest) async throws -> String {
        try Task.checkCancellation()
        let engine = engine
        let maximumOutputTokens = maximumOutputTokens
        let response = try await Self.perform(on: queue) {
            try Self.generateSynchronously(
                request,
                engine: engine,
                maximumOutputTokens: maximumOutputTokens
            )
        }
        try Task.checkCancellation()
        return response
    }

    private static func generateSynchronously(
        _ request: LocalGemmaGenerationRequest,
        engine: LiteRTEngineHandle,
        maximumOutputTokens: Int
    ) throws -> String {
        guard let sessionConfiguration = litert_lm_session_config_create() else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_session_config_delete(sessionConfiguration) }
        litert_lm_session_config_set_apply_prompt_template(sessionConfiguration, true)

        guard let sampler = litert_lm_sampler_params_create(kLiteRtLmSamplerTypeGreedy) else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_sampler_params_delete(sampler) }
        litert_lm_session_config_set_sampler_params(sessionConfiguration, sampler)

        guard let conversationConfiguration = litert_lm_conversation_config_create() else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_conversation_config_delete(conversationConfiguration) }
        litert_lm_conversation_config_set_session_config(
            conversationConfiguration,
            sessionConfiguration
        )

        let systemMessage = try Self.messageJSON(
            role: "system",
            text: request.systemInstruction
        )
        litert_lm_conversation_config_set_system_message(
            conversationConfiguration,
            systemMessage
        )
        var constraintProvider = kLiteRtLmConstraintProviderTypeLlGuidance
        litert_lm_conversation_config_set_constraint_provider(
            conversationConfiguration,
            &constraintProvider
        )
        litert_lm_conversation_config_set_enable_constrained_decoding(
            conversationConfiguration,
            true
        )

        guard let conversation = litert_lm_conversation_create(
            engine.pointer,
            conversationConfiguration
        ) else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_conversation_delete(conversation) }

        guard let optionalArguments = litert_lm_conversation_optional_args_create() else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_conversation_optional_args_delete(optionalArguments) }
        litert_lm_conversation_optional_args_set_max_output_tokens(
            optionalArguments,
            Int32(min(request.maximumOutputTokens, maximumOutputTokens))
        )
        let schema = try Self.responseSchemaJSON(
            approvedActionIDs: request.approvedActionIDs
        )
        litert_lm_conversation_optional_args_set_constraint(
            optionalArguments,
            kLiteRtLmConstraintTypeJsonSchema,
            schema
        )

        let userMessage = try Self.messageJSON(role: "user", text: request.prompt)
        guard let response = litert_lm_conversation_send_message(
            conversation,
            userMessage,
            nil,
            optionalArguments
        ) else {
            throw LocalGemmaProviderError.generationFailed
        }
        defer { litert_lm_json_response_delete(response) }

        guard let responseCharacters = litert_lm_json_response_get_string(response) else {
            throw LocalGemmaProviderError.generationFailed
        }
        return try Self.text(fromResponseJSON: String(cString: responseCharacters))
    }

    private static func loadRuntime(
        configuration: LocalGemmaConfiguration
    ) throws -> LoadedLiteRTRuntime {
        try Self.validate(configuration)
        if configuration.verifiesModelChecksum {
            try Self.verifyModelArtifact(configuration)
        }

        let backend: String
        switch configuration.backend {
        case .cpu:
            backend = "cpu"
        case .gpu:
            backend = "gpu"
        }

        guard let settings = litert_lm_engine_settings_create(
            configuration.modelURL.path,
            backend,
            nil,
            nil
        ) else {
            throw LocalGemmaProviderError.runtimeInitializationFailed
        }
        defer { litert_lm_engine_settings_delete(settings) }
        litert_lm_engine_settings_set_max_num_tokens(
            settings,
            Int32(configuration.maximumContextTokens)
        )
        litert_lm_engine_settings_set_cache_dir(settings, configuration.cacheURL.path)
        if case .cpu(let threadCount) = configuration.backend,
           let threadCount {
            guard threadCount > 0 else {
                throw LocalGemmaProviderError.invalidConfiguration
            }
            litert_lm_engine_settings_set_num_threads(settings, Int32(threadCount))
        }

        guard let loadedEngine = litert_lm_engine_create(settings) else {
            throw LocalGemmaProviderError.runtimeInitializationFailed
        }
        return LoadedLiteRTRuntime(
            engine: LiteRTEngineHandle(pointer: loadedEngine),
            maximumOutputTokens: configuration.maximumOutputTokens
        )
    }

    private static func validate(_ configuration: LocalGemmaConfiguration) throws {
        guard configuration.maximumContextTokens > 0,
              configuration.maximumOutputTokens > 0,
              configuration.maximumOutputTokens < configuration.maximumContextTokens else {
            throw LocalGemmaProviderError.invalidConfiguration
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: configuration.modelURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue == false else {
            throw LocalGemmaProviderError.modelFileMissing
        }

        try FileManager.default.createDirectory(
            at: configuration.cacheURL,
            withIntermediateDirectories: true
        )
    }

    private static func verifyModelArtifact(
        _ configuration: LocalGemmaConfiguration
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: configuration.modelURL.path
        )
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value == configuration.model.fileSize else {
            throw LocalGemmaProviderError.modelFileSizeMismatch
        }

        let handle = try FileHandle(forReadingFrom: configuration.modelURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard data.isEmpty == false else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == configuration.model.sha256.lowercased() else {
            throw LocalGemmaProviderError.modelChecksumMismatch
        }
    }

    private static func messageJSON(role: String, text: String) throws -> String {
        let object: [String: Any] = [
            "role": role,
            "content": [["type": "text", "text": text]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LocalGemmaProviderError.generationFailed
        }
        return json
    }

    private static func responseSchemaJSON(
        approvedActionIDs: [String]
    ) throws -> String {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "message": ["type": "string"],
                "actionIDs": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 3,
                    "uniqueItems": true,
                    "items": [
                        "type": "string",
                        "enum": approvedActionIDs
                    ]
                ]
            ],
            "required": ["title", "message", "actionIDs"],
            "additionalProperties": false
        ]
        let data = try JSONSerialization.data(withJSONObject: schema)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LocalGemmaProviderError.generationFailed
        }
        return json
    }

    private static func text(fromResponseJSON responseJSON: String) throws -> String {
        guard let data = responseJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else {
            throw LocalGemmaProviderError.generationFailed
        }
        let text = content.compactMap { item -> String? in
            guard item["type"] as? String == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: " ")
        guard text.isEmpty == false else {
            throw LocalGemmaProviderError.generationFailed
        }
        return text
    }

    private static func perform<Value: Sendable>(
        on queue: DispatchQueue,
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct LoadedLiteRTRuntime: Sendable {
    let engine: LiteRTEngineHandle
    let maximumOutputTokens: Int
}

private final class LiteRTEngineHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        litert_lm_engine_delete(pointer)
    }
}
