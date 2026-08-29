import CryptoKit
import Foundation
import SwiftMend
import SwiftMendLiteRT
import Testing
@testable import SwiftMendDemo

struct LocalGemmaModelStoreTests {
    @Test("A verified model is atomically installed in Application Support")
    func validImportInstallsCanonicalModel() async throws {
        let fixture = try ModelStoreFixture(data: Data("verified model".utf8))
        defer { fixture.remove() }
        let store = fixture.makeStore()

        let installedURL = try await store.importModel(from: fixture.sourceURL)

        #expect(installedURL.lastPathComponent == "model.litertlm")
        #expect(installedURL.path.contains("SwiftMendDemo/Models"))
        #expect(try Data(contentsOf: installedURL) == fixture.data)
        #expect(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
        let resourceValues = try installedURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        #expect(resourceValues.isExcludedFromBackup == true)
        let directoryContents = try FileManager.default.contentsOfDirectory(
            at: installedURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(directoryContents.map(\.lastPathComponent) == ["model.litertlm"])
    }

    @Test("An imported model with the wrong size is rejected")
    func sizeMismatchIsRejected() async throws {
        let fixture = try ModelStoreFixture(
            data: Data("short".utf8),
            descriptorData: Data("expected model".utf8)
        )
        defer { fixture.remove() }
        let store = fixture.makeStore()

        do {
            _ = try await store.importModel(from: fixture.sourceURL)
            Issue.record("Expected the mismatched model size to be rejected.")
        } catch let error as LocalGemmaModelStoreError {
            #expect(
                error == .modelFileSizeMismatch(
                    expected: Int64(fixture.descriptorData.count),
                    actual: Int64(fixture.data.count)
                )
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: fixture.installedURL.path) == false)
    }

    @Test("An imported model with the wrong checksum is rejected")
    func checksumMismatchIsRejected() async throws {
        let sourceData = Data("actual model".utf8)
        let expectedData = Data("expect model".utf8)
        #expect(sourceData.count == expectedData.count)
        let fixture = try ModelStoreFixture(data: sourceData, descriptorData: expectedData)
        defer { fixture.remove() }
        let store = fixture.makeStore()

        await #expect(throws: LocalGemmaModelStoreError.modelChecksumMismatch) {
            try await store.importModel(from: fixture.sourceURL)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.installedURL.path) == false)
    }

    @Test("A verified installation is discovered after the store is recreated")
    func installedModelPersistsAcrossStoreInstances() async throws {
        let fixture = try ModelStoreFixture(data: Data("persistent model".utf8))
        defer { fixture.remove() }
        let firstStore = fixture.makeStore()
        let installedURL = try await firstStore.importModel(from: fixture.sourceURL)
        let restoredStore = fixture.makeStore()

        let restoredModelURL = try await restoredStore.installedModelURL()
        let restoredURL = try #require(restoredModelURL)

        #expect(restoredURL == installedURL)
    }

    @Test("A failed replacement preserves the verified installed model")
    func failedReplacementPreservesInstalledModel() async throws {
        let verifiedData = Data("verified model".utf8)
        let fixture = try ModelStoreFixture(data: verifiedData)
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let installedURL = try await store.importModel(from: fixture.sourceURL)
        let invalidData = Data("tampered model".utf8)
        #expect(invalidData.count == verifiedData.count)
        try invalidData.write(to: fixture.sourceURL)

        await #expect(throws: LocalGemmaModelStoreError.modelChecksumMismatch) {
            try await store.importModel(from: fixture.sourceURL)
        }

        #expect(try Data(contentsOf: installedURL) == verifiedData)
    }

    @Test("Only LiteRT model files are accepted")
    func invalidFileExtensionIsRejected() async throws {
        let fixture = try ModelStoreFixture(
            data: Data("verified model".utf8),
            sourceFileName: "model.bin"
        )
        defer { fixture.remove() }
        let store = fixture.makeStore()

        await #expect(throws: LocalGemmaModelStoreError.invalidFileExtension) {
            try await store.importModel(from: fixture.sourceURL)
        }
    }
}

@MainActor
struct LocalGemmaModelCoordinatorTests {
    @Test("Importing loads one provider and caches it")
    func importLoadsAndCachesProvider() async throws {
        let fixture = try ModelStoreFixture(data: Data("verified model".utf8))
        defer { fixture.remove() }
        let loader = RecordingLocalProviderLoader()
        let coordinator = LocalGemmaModelCoordinator(
            store: fixture.makeStore(),
            providerLoader: { configuration in
                await loader.load(configuration)
            }
        )

        await coordinator.importModel(from: fixture.sourceURL)
        #expect(coordinator.state == .ready)
        #expect(coordinator.provider != nil)
        #expect(await loader.loadCount == 1)

        await coordinator.restoreInstalledModel()
        #expect(coordinator.state == .ready)
        #expect(await loader.loadCount == 1)
    }

    @Test("A missing installation remains honestly unavailable")
    func missingInstallationIsUnavailable() async throws {
        let fixture = try ModelStoreFixture(data: Data("unused model".utf8))
        defer { fixture.remove() }
        let loader = RecordingLocalProviderLoader()
        let coordinator = LocalGemmaModelCoordinator(
            store: fixture.makeStore(),
            providerLoader: { configuration in
                await loader.load(configuration)
            }
        )

        await coordinator.restoreInstalledModel()

        #expect(coordinator.state == .unavailable)
        #expect(coordinator.provider == nil)
        #expect(await loader.loadCount == 0)
    }

    @Test("Integrity failures do not expose a provider")
    func failedImportHasSafeFailureState() async throws {
        let data = Data("actual model".utf8)
        let expectedData = Data("expect model".utf8)
        let fixture = try ModelStoreFixture(data: data, descriptorData: expectedData)
        defer { fixture.remove() }
        let coordinator = LocalGemmaModelCoordinator(store: fixture.makeStore())

        await coordinator.importModel(from: fixture.sourceURL)

        #expect(
            coordinator.state
                == .failed(reason: "The selected model failed integrity verification.")
        )
        #expect(coordinator.provider == nil)
    }
}

private struct ModelStoreFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let sourceURL: URL
    let data: Data
    let descriptorData: Data
    let descriptor: LocalGemmaModelDescriptor

    var installedURL: URL {
        applicationSupportURL.appending(path: "SwiftMendDemo/Models/model.litertlm")
    }

    init(
        data: Data,
        descriptorData: Data? = nil,
        sourceFileName: String = "model.litertlm"
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "SwiftMendModelStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: sourceFileName)
        try data.write(to: sourceURL)
        let descriptorData = descriptorData ?? data

        self.rootURL = rootURL
        self.applicationSupportURL = rootURL.appending(
            path: "Application Support",
            directoryHint: .isDirectory
        )
        self.sourceURL = sourceURL
        self.data = data
        self.descriptorData = descriptorData
        self.descriptor = LocalGemmaModelDescriptor(
            id: "swiftmend/test-model",
            revision: "test-revision",
            fileName: "model.litertlm",
            fileSize: Int64(descriptorData.count),
            sha256: SHA256.hash(data: descriptorData)
                .map { String(format: "%02x", $0) }
                .joined(),
            parameterCount: 1
        )
    }

    func makeStore() -> LocalGemmaModelStore {
        LocalGemmaModelStore(
            fileManager: .default,
            applicationSupportDirectory: applicationSupportURL,
            descriptor: descriptor
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor RecordingLocalProviderLoader {
    private(set) var loadCount = 0

    func load(
        _ configuration: LocalGemmaConfiguration
    ) -> any RecoveryModelProviding {
        loadCount += 1
        return StubLocalRecoveryModelProvider()
    }
}

private struct StubLocalRecoveryModelProvider: RecoveryModelProviding {
    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        RecoveryAdvice(
            title: "Local recovery",
            message: "Choose an approved action.",
            actions: Array(request.approvedActions.prefix(1))
        )
    }
}
