import CryptoKit
import Foundation
import SwiftMendLiteRT

enum LocalGemmaModelStoreError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case invalidFileExtension
    case sourceMissing
    case modelFileSizeMismatch(expected: Int64, actual: Int64)
    case modelChecksumMismatch
}

actor LocalGemmaModelStore {
    private static let modelDirectoryName = "Models"
    private static let cacheDirectoryName = "LiteRTCache"
    private static let containerDirectoryName = "SwiftMendDemo"

    private let fileManager: FileManager
    private let applicationSupportDirectory: URL?
    private let descriptor: LocalGemmaModelDescriptor

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        descriptor: LocalGemmaModelDescriptor = .swiftMendGemma3_270MRecovery
    ) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.descriptor = descriptor
    }

    func installedModelURL() throws -> URL? {
        let modelURL = try canonicalModelURL()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: modelURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue == false else {
            throw LocalGemmaModelStoreError.sourceMissing
        }

        try validateModel(at: modelURL)
        return modelURL
    }

    func importModel(from sourceURL: URL) throws -> URL {
        guard sourceURL.pathExtension.lowercased() == "litertlm" else {
            throw LocalGemmaModelStoreError.invalidFileExtension
        }

        let accessedSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false else {
            throw LocalGemmaModelStoreError.sourceMissing
        }

        let destinationURL = try canonicalModelURL()
        let modelDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let stagingURL = modelDirectory.appending(
            path: ".model-import-\(UUID().uuidString).litertlm"
        )
        defer { try? fileManager.removeItem(at: stagingURL) }

        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        try validateModel(at: stagingURL)
        try excludeFromBackup(stagingURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }

        try excludeFromBackup(destinationURL)
        return destinationURL
    }

    func configuration(for modelURL: URL) throws -> LocalGemmaConfiguration {
        let cacheURL = try containerDirectory().appending(
            path: Self.cacheDirectoryName,
            directoryHint: .isDirectory
        )
        return LocalGemmaConfiguration(
            modelURL: modelURL,
            model: descriptor,
            backend: .cpu(),
            cacheURL: cacheURL
        )
    }

    private func canonicalModelURL() throws -> URL {
        try containerDirectory()
            .appending(path: Self.modelDirectoryName, directoryHint: .isDirectory)
            .appending(path: "model.litertlm", directoryHint: .notDirectory)
    }

    private func containerDirectory() throws -> URL {
        guard let applicationSupportDirectory else {
            throw LocalGemmaModelStoreError.applicationSupportUnavailable
        }
        return applicationSupportDirectory.appending(
            path: Self.containerDirectoryName,
            directoryHint: .isDirectory
        )
    }

    private func validateModel(at url: URL) throws {
        try LocalGemmaModelManifest(model: descriptor).validate()
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualSize == descriptor.fileSize else {
            throw LocalGemmaModelStoreError.modelFileSizeMismatch(
                expected: descriptor.fileSize,
                actual: actualSize
            )
        }

        guard try sha256(for: url) == descriptor.sha256.lowercased() else {
            throw LocalGemmaModelStoreError.modelChecksumMismatch
        }
    }

    private func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard data.isEmpty == false else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func excludeFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}
