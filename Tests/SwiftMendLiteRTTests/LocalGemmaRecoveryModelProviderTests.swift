import Foundation
import SwiftMend
import Testing
@testable import SwiftMendLiteRT

struct LocalGemmaRecoveryModelProviderTests {
    private let approvedActions = [
        RecoveryAction(id: "check-wifi", title: "Check Wi-Fi"),
        RecoveryAction(id: "try-again", title: "Try Again")
    ]

    @Test("Local Gemma maps selected IDs to canonical developer actions")
    func validResponseUsesCanonicalActions() async throws {
        let generator = RecordingLocalGenerator(
            result: .success(
                #"{"title":"Reconnect","message":"Check Wi-Fi, then retry.","actionIDs":["check-wifi","try-again"]}"#
            )
        )
        let provider = LocalGemmaRecoveryModelProvider(generator: generator)

        let advice = try await provider.recoveryAdvice(for: modelRequest())
        let generationRequest = try #require(await generator.request)

        #expect(advice.actions == approvedActions)
        #expect(generationRequest.prompt.contains("profile sync"))
        #expect(generationRequest.prompt.contains("check-wifi"))
        #expect(generationRequest.systemInstruction == RecoveryModelPrompt.systemInstruction)
        #expect(generationRequest.approvedActionIDs == approvedActions.map(\.id))
        #expect(generationRequest.maximumOutputTokens == 256)
    }

    @Test("Local Gemma accepts fenced JSON and preserves canonical titles")
    func fencedResponseUsesCanonicalTitle() async throws {
        let generator = RecordingLocalGenerator(
            result: .success(
                """
                ```json
                {"title":"Retry sync","message":"Reconnect, then retry.","actionIDs":["try-again"]}
                ```
                """
            )
        )
        let provider = LocalGemmaRecoveryModelProvider(generator: generator)

        let advice = try await provider.recoveryAdvice(for: modelRequest())

        #expect(advice.actions == [approvedActions[1]])
    }

    @Test("Unknown and duplicate local action IDs are rejected")
    func invalidActionIDsAreRejected() async {
        let invalidResponses = [
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["not-approved"]}"#,
            #"{"title":"Recover","message":"Choose an option.","actionIDs":["try-again","try-again"]}"#
        ]

        for response in invalidResponses {
            let provider = LocalGemmaRecoveryModelProvider(
                generator: RecordingLocalGenerator(result: .success(response))
            )
            await #expect(throws: LocalGemmaProviderError.invalidResponse) {
                try await provider.recoveryAdvice(for: modelRequest())
            }
        }
    }

    @Test("Malformed local approved-action catalogs are rejected before generation")
    func malformedCatalogsAreRejected() async {
        let generator = RecordingLocalGenerator(
            result: .success(
                #"{"title":"Recover","message":"Try again.","actionIDs":["try-again"]}"#
            )
        )
        let malformedCatalogs = [
            [],
            [RecoveryAction(id: "", title: "Missing ID")],
            [RecoveryAction(id: "retry", title: "  ")],
            [
                RecoveryAction(id: "retry", title: "Try Again"),
                RecoveryAction(id: "retry", title: "Retry Request")
            ]
        ]

        for actions in malformedCatalogs {
            let provider = LocalGemmaRecoveryModelProvider(generator: generator)
            await #expect(throws: LocalGemmaProviderError.invalidRequest) {
                try await provider.recoveryAdvice(for: modelRequest(approvedActions: actions))
            }
        }
        #expect(await generator.requestCount == 0)
    }

    @Test("Generator failures propagate so RecoveryEngine can use its fallback")
    func generatorFailurePropagates() async {
        let provider = LocalGemmaRecoveryModelProvider(
            generator: RecordingLocalGenerator(result: .failure(.unavailable))
        )

        await #expect(throws: LocalGeneratorError.unavailable) {
            try await provider.recoveryAdvice(for: modelRequest())
        }
    }

    @Test("The pinned model descriptor identifies the QAT 4-bit artifact")
    func pinnedModelDescriptorIsExact() {
        let model = LocalGemmaModelDescriptor.gemma3_1BInstructionTunedQAT4Bit

        #expect(model.id == "litert-community/Gemma3-1B-IT")
        #expect(model.fileName == "gemma3-1b-it-int4.litertlm")
        #expect(model.fileSize == 584_417_280)
        #expect(model.sha256.count == 64)
        #expect(model.revision.count == 40)
        #expect(model.parameterCount == 1_000_000_000)
    }

    @Test("The general configuration uses the verified 270M CPU default")
    func generalConfigurationUsesVerified270MDefault() {
        let configuration = LocalGemmaConfiguration(
            modelURL: URL(filePath: "/tmp/model.litertlm"),
            cacheURL: URL(filePath: "/tmp/cache")
        )

        #expect(configuration.model == .swiftMendGemma3_270MRecovery)
        #expect(configuration.backend == .cpu())
        #expect(configuration.verifiesModelChecksum)
    }

    @Test("The verified 270M descriptor pins the converted recovery artifact")
    func verified270MModelDescriptorIsExact() {
        let model = LocalGemmaModelDescriptor.swiftMendGemma3_270MRecovery

        #expect(model.id == "swiftmend/gemma-3-270m-recovery")
        #expect(
            model.revision
                == "2cca65c67604e87c13a0235d9a7237be558de71bd819f6c4a11c55441230b4cb"
        )
        #expect(model.fileName == "model.litertlm")
        #expect(model.fileSize == 284_700_672)
        #expect(
            model.sha256
                == "9e7aa6f19e3342a13f56e3ac3241996094e962721c1b4fa4fa5043442b140ee0"
        )
        #expect(model.parameterCount == 270_000_000)
    }

    @Test("The verified 270M preset always selects the CPU backend")
    func verified270MPresetUsesCPU() {
        let configuration = LocalGemmaConfiguration.swiftMendGemma3_270MRecovery(
            modelURL: URL(filePath: "/tmp/model.litertlm"),
            cacheURL: URL(filePath: "/tmp/cache"),
            cpuThreadCount: 4
        )

        #expect(configuration.model == .swiftMendGemma3_270MRecovery)
        #expect(configuration.backend == .cpu(threadCount: 4))
        #expect(configuration.verifiesModelChecksum)
    }

    @Test("The verified 270M artifact rejects the unsupported GPU backend")
    func verified270MArtifactRejectsGPU() async {
        let configuration = LocalGemmaConfiguration(
            modelURL: URL(filePath: "/tmp/model.litertlm"),
            model: .swiftMendGemma3_270MRecovery,
            backend: .gpu,
            cacheURL: URL(filePath: "/tmp/cache")
        )

        await #expect(throws: LocalGemmaProviderError.invalidConfiguration) {
            try await LocalGemmaRecoveryModelProvider.load(configuration: configuration)
        }
    }

    @Test("The C bridge receives system content rather than a nested message")
    func systemContentPayloadMatchesConversationAPI() throws {
        let instruction = "Return approved recovery action IDs only."

        let payload = try LiteRTGemmaTextGenerator.systemContentJSON(text: instruction)
        let decoded = try JSONDecoder().decode(String.self, from: Data(payload.utf8))

        #expect(decoded == instruction)
    }

    @Test("The local JSON schema uses only supported LLGuidance keywords")
    func constrainedSchemaIsLiteRTCompatible() throws {
        let payload = try LiteRTGemmaTextGenerator.responseSchemaJSON(
            approvedActionIDs: approvedActions.map(\.id)
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        let properties = try #require(root["properties"] as? [String: Any])
        let actionIDs = try #require(properties["actionIDs"] as? [String: Any])
        let items = try #require(actionIDs["items"] as? [String: Any])

        #expect(actionIDs["uniqueItems"] == nil)
        #expect(actionIDs["minItems"] as? Int == 1)
        #expect(actionIDs["maxItems"] as? Int == 3)
        #expect(items["enum"] as? [String] == approvedActions.map(\.id))
    }

    @Test("Missing model artifacts fail before LiteRT initialization")
    func missingModelFailsBeforeInitialization() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let configuration = LocalGemmaConfiguration(
            modelURL: temporaryDirectory.appending(
                path: LocalGemmaModelDescriptor.gemma3_1BInstructionTunedQAT4Bit.fileName
            ),
            model: .gemma3_1BInstructionTunedQAT4Bit,
            backend: .gpu,
            cacheURL: temporaryDirectory.appending(path: "cache")
        )

        await #expect(throws: LocalGemmaProviderError.modelFileMissing) {
            try await LocalGemmaRecoveryModelProvider.load(configuration: configuration)
        }
    }

    @Test("Model size mismatches fail before LiteRT initialization")
    func modelSizeMismatchFailsBeforeInitialization() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let modelURL = temporaryDirectory.appending(
            path: LocalGemmaModelDescriptor.gemma3_1BInstructionTunedQAT4Bit.fileName
        )
        try Data([0x01]).write(to: modelURL)
        let configuration = LocalGemmaConfiguration(
            modelURL: modelURL,
            model: .gemma3_1BInstructionTunedQAT4Bit,
            backend: .gpu,
            cacheURL: temporaryDirectory.appending(path: "cache")
        )

        await #expect(throws: LocalGemmaProviderError.modelFileSizeMismatch) {
            try await LocalGemmaRecoveryModelProvider.load(configuration: configuration)
        }
    }

    @Test("Model checksum mismatches fail before LiteRT initialization")
    func modelChecksumMismatchFailsBeforeInitialization() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let modelURL = temporaryDirectory.appending(path: "model.litertlm")
        try Data([0x01]).write(to: modelURL)
        let descriptor = LocalGemmaModelDescriptor(
            id: "test/model",
            revision: String(repeating: "0", count: 40),
            fileName: "model.litertlm",
            fileSize: 1,
            sha256: String(repeating: "0", count: 64),
            parameterCount: 1
        )
        let configuration = LocalGemmaConfiguration(
            modelURL: modelURL,
            model: descriptor,
            cacheURL: temporaryDirectory.appending(path: "cache")
        )

        await #expect(throws: LocalGemmaProviderError.modelChecksumMismatch) {
            try await LocalGemmaRecoveryModelProvider.load(configuration: configuration)
        }
    }

    @Test("Custom model manifests pin artifact identity for candidate benchmarks")
    func customManifestRoundTrip() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let modelURL = temporaryDirectory.appending(path: "candidate.litertlm")
        try Data([0x01, 0x02, 0x03]).write(to: modelURL)
        let manifest = try LocalGemmaModelManifest.create(
            for: modelURL,
            id: "swiftmend/gemma-3-270m-recovery",
            revision: "training-manifest-sha256",
            parameterCount: 270_000_000
        )
        let manifestURL = temporaryDirectory.appending(path: "manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        let loaded = try LocalGemmaModelManifest.load(from: manifestURL)

        #expect(loaded == manifest)
        #expect(loaded.model.fileName == modelURL.lastPathComponent)
        #expect(loaded.model.fileSize == 3)
        #expect(loaded.model.sha256.count == 64)
        #expect(loaded.model.parameterCount == 270_000_000)
    }

    private func modelRequest(
        approvedActions: [RecoveryAction]? = nil
    ) -> RecoveryModelRequest {
        RecoveryModelRequest(
            snapshot: ErrorSnapshot(
                domain: NSURLErrorDomain,
                code: NSURLErrorNotConnectedToInternet,
                message: "Offline"
            ),
            context: RecoveryContext(feature: "profile sync"),
            approvedActions: approvedActions ?? self.approvedActions
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SwiftMendLiteRTTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor RecordingLocalGenerator: LocalGemmaTextGenerating {
    private let result: Result<String, LocalGeneratorError>
    private(set) var request: LocalGemmaGenerationRequest?
    private(set) var requestCount = 0

    init(result: Result<String, LocalGeneratorError>) {
        self.result = result
    }

    func generate(_ request: LocalGemmaGenerationRequest) async throws -> String {
        self.request = request
        requestCount += 1
        return try result.get()
    }
}

private enum LocalGeneratorError: Error {
    case unavailable
}
