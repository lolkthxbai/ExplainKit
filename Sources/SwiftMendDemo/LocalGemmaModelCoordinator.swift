import Foundation
import Observation
import SwiftMend
import SwiftMendLiteRT

enum LocalGemmaModelState: Equatable, Sendable {
    case unavailable
    case importing
    case loading
    case ready
    case failed(reason: String)

    var isBusy: Bool {
        self == .importing || self == .loading
    }
}

typealias LocalGemmaProviderLoader = @Sendable (
    LocalGemmaConfiguration
) async throws -> any RecoveryModelProviding

@MainActor
@Observable
final class LocalGemmaModelCoordinator {
    private(set) var state: LocalGemmaModelState = .unavailable
    private(set) var provider: (any RecoveryModelProviding)?

    @ObservationIgnored private let store: LocalGemmaModelStore
    @ObservationIgnored private let providerLoader: LocalGemmaProviderLoader

    init(
        store: LocalGemmaModelStore = LocalGemmaModelStore(),
        providerLoader: @escaping LocalGemmaProviderLoader = { configuration in
            try await LocalGemmaRecoveryModelProvider.load(configuration: configuration)
        }
    ) {
        self.store = store
        self.providerLoader = providerLoader
    }

    func restoreInstalledModel() async {
        guard state.isBusy == false else { return }
        guard provider == nil else {
            state = .ready
            return
        }

        state = .loading
        do {
            guard let modelURL = try await store.installedModelURL() else {
                state = .unavailable
                return
            }
            try await loadProvider(modelURL: modelURL)
        } catch {
            handleFailure(error)
        }
    }

    func importModel(from sourceURL: URL) async {
        guard state.isBusy == false else { return }

        provider = nil
        state = .importing
        do {
            let modelURL = try await store.importModel(from: sourceURL)
            state = .loading
            try await loadProvider(modelURL: modelURL)
        } catch {
            handleFailure(error)
        }
    }

    private func loadProvider(modelURL: URL) async throws {
        let configuration = try await store.configuration(for: modelURL)
        let loadedProvider = try await providerLoader(configuration)
        try Task.checkCancellation()
        provider = loadedProvider
        state = .ready
    }

    private func handleFailure(_ error: any Error) {
        provider = nil
        state = .failed(reason: Self.failureReason(for: error))
    }

    private static func failureReason(for error: any Error) -> String {
        if error is CancellationError {
            return "Model setup was canceled."
        }

        if let storeError = error as? LocalGemmaModelStoreError {
            switch storeError {
            case .applicationSupportUnavailable:
                return "Application Support is unavailable."
            case .invalidFileExtension:
                return "Choose a .litertlm model file."
            case .sourceMissing:
                return "The selected model file is unavailable."
            case .modelFileSizeMismatch:
                return "The selected model does not match the verified SwiftMend model."
            case .modelChecksumMismatch:
                return "The selected model failed integrity verification."
            }
        }

        if let providerError = error as? LocalGemmaProviderError {
            switch providerError {
            case .modelFileMissing:
                return "The imported model file is unavailable."
            case .modelFileSizeMismatch, .modelChecksumMismatch:
                return "The imported model failed integrity verification."
            case .invalidConfiguration:
                return "The on-device model configuration is invalid."
            case .runtimeInitializationFailed:
                return "The on-device model could not be loaded."
            case .generationFailed, .invalidRequest, .invalidResponse:
                return "The on-device model is not ready."
            }
        }

        return "The on-device model could not be prepared."
    }
}
