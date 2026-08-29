import CryptoKit
import Foundation

public enum LocalGemmaBackend: Equatable, Sendable {
    case cpu(threadCount: Int? = nil)
    case gpu
}

public struct LocalGemmaModelDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let revision: String
    public let fileName: String
    public let fileSize: Int64
    public let sha256: String
    public let parameterCount: Int64

    public init(
        id: String,
        revision: String,
        fileName: String,
        fileSize: Int64,
        sha256: String,
        parameterCount: Int64
    ) {
        self.id = id
        self.revision = revision
        self.fileName = fileName
        self.fileSize = fileSize
        self.sha256 = sha256
        self.parameterCount = parameterCount
    }

    public static let gemma3_1BInstructionTunedQAT4Bit = LocalGemmaModelDescriptor(
        id: "litert-community/Gemma3-1B-IT",
        revision: "6d54daa71cfbffba6b2843c08eeb1a27e7430bf0",
        fileName: "gemma3-1b-it-int4.litertlm",
        fileSize: 584_417_280,
        sha256: "1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be",
        parameterCount: 1_000_000_000
    )

    /// The exact fine-tuned artifact that passed SwiftMend's held-out CPU evaluation.
    public static let swiftMendGemma3_270MRecovery = LocalGemmaModelDescriptor(
        id: "swiftmend/gemma-3-270m-recovery",
        revision: "2cca65c67604e87c13a0235d9a7237be558de71bd819f6c4a11c55441230b4cb",
        fileName: "model.litertlm",
        fileSize: 284_700_672,
        sha256: "9e7aa6f19e3342a13f56e3ac3241996094e962721c1b4fa4fa5043442b140ee0",
        parameterCount: 270_000_000
    )
}

public struct LocalGemmaModelManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let model: LocalGemmaModelDescriptor

    public init(schemaVersion: Int = 1, model: LocalGemmaModelDescriptor) {
        self.schemaVersion = schemaVersion
        self.model = model
    }

    public static func load(from url: URL) throws -> LocalGemmaModelManifest {
        let manifest = try JSONDecoder().decode(
            LocalGemmaModelManifest.self,
            from: Data(contentsOf: url)
        )
        try manifest.validate()
        return manifest
    }

    public static func create(
        for modelURL: URL,
        id: String,
        revision: String,
        parameterCount: Int64
    ) throws -> LocalGemmaModelManifest {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false else {
            throw LocalGemmaProviderError.modelFileMissing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw LocalGemmaProviderError.invalidConfiguration
        }
        let manifest = LocalGemmaModelManifest(
            model: LocalGemmaModelDescriptor(
                id: id,
                revision: revision,
                fileName: modelURL.lastPathComponent,
                fileSize: fileSize.int64Value,
                sha256: try sha256(for: modelURL),
                parameterCount: parameterCount
            )
        )
        try manifest.validate()
        return manifest
    }

    public func validate() throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard schemaVersion == 1,
              model.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              model.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              model.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              model.fileSize > 0,
              model.parameterCount > 0,
              model.sha256.count == 64,
              model.sha256.lowercased().unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw LocalGemmaProviderError.invalidConfiguration
        }
    }

    private static func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard data.isEmpty == false else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
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

    /// Creates a checksum-verifying CPU configuration for the verified 270M artifact.
    public static func swiftMendGemma3_270MRecovery(
        modelURL: URL,
        cacheURL: URL,
        cpuThreadCount: Int? = nil,
        maximumContextTokens: Int = 2_048,
        maximumOutputTokens: Int = 256
    ) -> LocalGemmaConfiguration {
        LocalGemmaConfiguration(
            modelURL: modelURL,
            model: .swiftMendGemma3_270MRecovery,
            backend: .cpu(threadCount: cpuThreadCount),
            cacheURL: cacheURL,
            maximumContextTokens: maximumContextTokens,
            maximumOutputTokens: maximumOutputTokens
        )
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
