import Foundation
import Observation
import SwiftMend

@MainActor
@Observable
final class DemoViewModel {
    private(set) var outcomes: [DemoScenario: DemoOutcome] = [:]
    private(set) var runningScenarios: Set<DemoScenario> = []
    private(set) var importSelectionFailure: String?

    @ObservationIgnored private let configuration: DemoConfiguration
    @ObservationIgnored private let diagnosticSource: OSLogDiagnosticSource
    @ObservationIgnored private let localGemmaCoordinator: LocalGemmaModelCoordinator

    init(
        configuration: DemoConfiguration,
        diagnosticSource: OSLogDiagnosticSource = OSLogDiagnosticSource(
            subsystem: "com.lolkthxbai.SwiftMendDemo",
            category: "recovery"
        ),
        localGemmaCoordinator: LocalGemmaModelCoordinator = LocalGemmaModelCoordinator()
    ) {
        self.configuration = configuration
        self.diagnosticSource = diagnosticSource
        self.localGemmaCoordinator = localGemmaCoordinator
    }

    var isGeminiConfigured: Bool {
        configuration.isGeminiConfigured
    }

    var localGemmaState: LocalGemmaModelState {
        localGemmaCoordinator.state
    }

    func isRunning(_ scenario: DemoScenario) -> Bool {
        runningScenarios.contains(scenario)
    }

    func run(_ scenario: DemoScenario) async {
        guard runningScenarios.insert(scenario).inserted else { return }
        defer { runningScenarios.remove(scenario) }

        let outcome = await scenario.run(
            using: diagnosticSource,
            modelProvider: modelProvider(for: scenario)
        )
        guard Task.isCancelled == false else { return }
        outcomes[scenario] = outcome
    }

    func restoreLocalModel() async {
        await localGemmaCoordinator.restoreInstalledModel()
    }

    func importLocalModel(from url: URL) async {
        importSelectionFailure = nil
        await localGemmaCoordinator.importModel(from: url)
    }

    func reportImportSelectionFailure() {
        importSelectionFailure = "The selected model file could not be opened."
    }

    func fallbackTrigger(for scenario: DemoScenario) -> String? {
        if let trigger = scenario.fallbackTrigger {
            return trigger.displayName
        }

        guard outcomes[scenario]?.source == .fallback else { return nil }
        switch scenario.modelRoute {
        case .gemini:
            if isGeminiConfigured {
                return "Gemini response unavailable, malformed, or insufficient"
            }
            return "Gemini unavailable · API key missing"
        case .localGemma:
            switch localGemmaState {
            case .unavailable:
                return "On-device Gemma unavailable · verified model not imported"
            case .importing:
                return "On-device Gemma unavailable · model import in progress"
            case .loading:
                return "On-device Gemma unavailable · model loading"
            case .ready:
                return "On-device Gemma response malformed or insufficient"
            case .failed(let reason):
                return "On-device Gemma unavailable · \(reason)"
            }
        case .simulatedUnavailable, .simulatedInvalidResponse, .none:
            return nil
        }
    }

    private func modelProvider(
        for scenario: DemoScenario
    ) -> (any RecoveryModelProviding)? {
        switch scenario.modelRoute {
        case .gemini:
            configuration.geminiProvider
        case .localGemma:
            localGemmaCoordinator.provider
        case .simulatedUnavailable, .simulatedInvalidResponse, .none:
            nil
        }
    }
}
