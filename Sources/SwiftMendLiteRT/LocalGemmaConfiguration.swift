import Foundation

public enum LocalGemmaBackend: Equatable, Sendable {
    case cpu(threadCount: Int? = nil)
    case gpu
}

public struct LocalGemmaModelDescriptor: Equatable, Sendable {
    public let id: String
    public let revision: String
    public let fileName: String
    public let fileSize: Int64
    public let sha256: String

    public init(
        id: String,
        revision: String,
        fileName: String,
        fileSize: Int64,
        sha256: String
    ) {
        self.id = id
        self.revision = revision
        self.fileName = fileName
        self.fileSize = fileSize
        self.sha256 = sha256
    }

    public static let gemma3_1BInstructionTunedQAT4Bit = LocalGemmaModelDescriptor(
        id: "litert-community/Gemma3-1B-IT",
        revision: "6d54daa71cfbffba6b2843c08eeb1a27e7430bf0",
        fileName: "gemma3-1b-it-int4.litertlm",
        fileSize: 584_417_280,
        sha256: "1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be"
    )
}

public struct LocalGemmaConfiguration: Equatable, Sendable {
    public let modelURL: URL
    public let model: LocalGemmaModelDescriptor
    public let backend: LocalGemmaBackend
    public let cacheURL: URL
    public let maximumContextTokens: Int
    public let maximumOutputTokens: Int
    public let verifiesModelChecksum: Bool

    public init(
        modelURL: URL,
        model: LocalGemmaModelDescriptor = .gemma3_1BInstructionTunedQAT4Bit,
        backend: LocalGemmaBackend = .gpu,
        cacheURL: URL,
        maximumContextTokens: Int = 2_048,
        maximumOutputTokens: Int = 256,
        verifiesModelChecksum: Bool = true
    ) {
        self.modelURL = modelURL
        self.model = model
        self.backend = backend
        self.cacheURL = cacheURL
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.verifiesModelChecksum = verifiesModelChecksum
    }
}

public enum LocalGemmaProviderError: Error, Equatable, Sendable {
    case invalidConfiguration
    case modelFileMissing
    case modelFileSizeMismatch
    case modelChecksumMismatch
    case runtimeInitializationFailed
    case generationFailed
    case invalidRequest
    case invalidResponse
}
