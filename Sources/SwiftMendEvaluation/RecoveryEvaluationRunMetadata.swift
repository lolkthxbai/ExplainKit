import Foundation

public struct RecoveryEvaluationRunMetadata: Codable, Equatable, Sendable {
    public let model: RecoveryEvaluationModelIdentity
    public let runtime: String
    public let backend: String
    public let hardwareModel: String
    public let operatingSystem: String

    public init(
        model: RecoveryEvaluationModelIdentity,
        runtime: String,
        backend: String,
        hardwareModel: String,
        operatingSystem: String
    ) {
        self.model = model
        self.runtime = runtime
        self.backend = backend
        self.hardwareModel = hardwareModel
        self.operatingSystem = operatingSystem
    }

    public func validate() throws {
        try model.validate()
        guard runtime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              hardwareModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              operatingSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw RecoveryEvaluationRunMetadataError.invalidEnvironment
        }
    }

    var environmentFingerprint: [String] {
        [runtime, backend, hardwareModel, operatingSystem]
    }
}

public struct RecoveryEvaluationModelIdentity: Codable, Equatable, Sendable {
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

    public func validate() throws {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              fileSize > 0,
              parameterCount > 0,
              sha256.count == 64,
              sha256.lowercased().unicodeScalars.allSatisfy(hexadecimal.contains) else {
            throw RecoveryEvaluationRunMetadataError.invalidModelIdentity
        }
    }
}

public enum RecoveryEvaluationRunMetadataError: Error, Equatable, Sendable {
    case invalidModelIdentity
    case invalidEnvironment
}
