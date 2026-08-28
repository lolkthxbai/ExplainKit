import ExplainKit
import Foundation
import Testing
@testable import ExplainKitDemo

struct DemoScenarioTests {
    private let source = OSLogDiagnosticSource(
        subsystem: "com.example.ExplainKitTests",
        category: "demo"
    )

    @Test("Password scenario resolves through its approved rule")
    func passwordScenarioUsesRule() async {
        let outcome = await DemoScenario.passwordRejected.run(using: source)

        #expect(outcome.snapshot.domain == "DemoAuth")
        #expect(outcome.advice.title == "Choose a stronger password")
        #expect(outcome.advice.actions.map(\.id) == ["edit-password"])
        #expect(outcome.source == .developerRule(id: "password-policy"))
    }

    @Test("Offline scenario resolves through local fallback")
    func offlineScenarioUsesFallback() async {
        let outcome = await DemoScenario.noInternet.run(using: source)

        #expect(outcome.snapshot.code == -1009)
        #expect(outcome.advice.title == "Reconnect to the internet")
        #expect(outcome.advice.actions.count == 3)
        #expect(outcome.source == .fallback)
    }

    @Test("Live Gemma scenario uses model advice when configured")
    func liveScenarioUsesModel() async {
        let modelAdvice = RecoveryAdvice(
            title: "Switch delivery methods",
            message: "Choose shipping, then retry checkout.",
            actions: [RecoveryAction(id: "shipping", title: "Choose Shipping")]
        )

        let outcome = await DemoScenario.liveGemma.run(
            using: source,
            modelProvider: MockRecoveryModelProvider(returning: modelAdvice)
        )

        #expect(outcome.advice == modelAdvice)
        #expect(outcome.source == .model)
    }

    @Test("Live Gemma scenario falls back when the provider fails")
    func liveScenarioFallsBack() async {
        let outcome = await DemoScenario.liveGemma.run(
            using: source,
            modelProvider: MockRecoveryModelProvider(failingWith: .unavailable)
        )

        #expect(outcome.advice.title == "Choose another delivery option")
        #expect(outcome.source == .fallback)
    }

    @Test("Demo configuration detects the API key without calling the network")
    func configurationDetectsAPIKey() {
        let configured = DemoConfiguration(environment: ["GEMINI_API_KEY": "test-api-key"])
        let missing = DemoConfiguration(environment: [:])

        #expect(configured.isLiveGemmaConfigured)
        #expect(missing.isLiveGemmaConfigured == false)
    }

    @Test("Gemma provider failures are classified into safe diagnostics")
    func gemmaProviderFailuresAreClassified() {
        #expect(DemoModelFailure(error: GemmaProviderError.invalidConfiguration) == .invalidConfiguration)
        #expect(DemoModelFailure(error: GemmaProviderError.invalidResponse) == .invalidResponse)
        #expect(DemoModelFailure(error: GemmaProviderError.httpStatus(404)) == .httpStatus(404))
    }

    @Test("Transport and unexpected failures are classified without their descriptions")
    func nonProviderFailuresAreClassified() {
        #expect(DemoModelFailure(error: URLError(.notConnectedToInternet)) == .transport(-1009))
        #expect(DemoModelFailure(error: DemoTestError.unexpected) == .unexpected)
    }
}

private enum DemoTestError: Error {
    case unexpected
}
