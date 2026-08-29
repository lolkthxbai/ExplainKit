import Foundation
import SwiftMend
import Testing
@testable import SwiftMendDemo

struct DemoScenarioTests {
    private let source = OSLogDiagnosticSource(
        subsystem: "com.example.SwiftMendTests",
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

    @Test(
        "Gemma scenarios use model advice constrained to canonical actions",
        arguments: [DemoScenario.liveGemmaStorePickup, .liveGemmaPhotoUpload]
    )
    func gemmaScenariosUseConstrainedModelAdvice(scenario: DemoScenario) async throws {
        let approvedAction = try #require(scenario.approvedModelActions.first)
        let provider = CapturingDemoProvider(
            advice: RecoveryAdvice(
                title: "Model explanation",
                message: "Choose one of the available recovery options.",
                actions: [RecoveryAction(id: approvedAction.id, title: "Model changed the title")]
            )
        )

        let outcome = await scenario.run(using: source, modelProvider: provider)
        let request = try #require(await provider.request)

        #expect(outcome.advice.actions == [approvedAction])
        #expect(outcome.source == .model)
        #expect(request.approvedActions == scenario.approvedModelActions)
    }

    @Test(
        "Gemma scenarios use local fallbacks when the provider is unavailable",
        arguments: [DemoScenario.liveGemmaStorePickup, .liveGemmaPhotoUpload]
    )
    func gemmaScenariosFallBack(scenario: DemoScenario) async {
        let outcome = await scenario.run(
            using: source,
            modelProvider: MockRecoveryModelProvider(failingWith: .unavailable)
        )

        #expect(outcome.source == .fallback)
        #expect(outcome.advice.actions.isEmpty == false)
    }

    @Test("Photo upload sends reviewed size context and its approved action catalog")
    func photoUploadRequestContainsReviewedContext() async throws {
        let scenario = DemoScenario.liveGemmaPhotoUpload
        let action = try #require(scenario.approvedModelActions.first)
        let provider = CapturingDemoProvider(
            advice: RecoveryAdvice(
                title: "Use a smaller photo",
                message: "Choose a smaller image, then retry.",
                actions: [action]
            )
        )

        let outcome = await scenario.run(using: source, modelProvider: provider)
        let request = try #require(await provider.request)

        #expect(outcome.snapshot.domain == "DemoUpload")
        #expect(outcome.snapshot.code == 3001)
        #expect(request.context.feature == "profile photo upload")
        #expect(request.context.attributes["fileSizeMB"] == "18")
        #expect(request.context.attributes["maximumFileSizeMB"] == "10")
        #expect(request.context.attributes["fileType"] == "HEIC")
        #expect(request.approvedActions.map(\.id) == [
            "choose-smaller-photo",
            "compress-photo",
            "try-again"
        ])
    }

    @Test("Only the two hosted scenarios use Gemma")
    func usesGemmaIdentifiesHostedScenarios() {
        let gemmaScenarios = DemoScenario.allCases.filter(\.usesGemma)

        #expect(gemmaScenarios == [.liveGemmaStorePickup, .liveGemmaPhotoUpload])
        #expect(DemoScenario.passwordRejected.usesGemma == false)
        #expect(DemoScenario.noInternet.usesGemma == false)
    }

    @Test("Demo configuration detects the API key without calling the network")
    func configurationDetectsAPIKey() {
        let configured = DemoConfiguration(environment: ["GEMINI_API_KEY": "test-api-key"])
        let bundleConfigured = DemoConfiguration(environment: [:], bundleAPIKey: "test-bundle-key")
        let missing = DemoConfiguration(environment: [:], bundleAPIKey: nil)

        #expect(configured.isLiveGemmaConfigured)
        #expect(bundleConfigured.isLiveGemmaConfigured)
        #expect(missing.isLiveGemmaConfigured == false)
    }

    @Test("Gemma provider failures are classified into safe diagnostics")
    func gemmaProviderFailuresAreClassified() {
        #expect(DemoModelFailure(error: GemmaProviderError.invalidConfiguration) == .invalidConfiguration)
        #expect(DemoModelFailure(error: GemmaProviderError.invalidRequest) == .invalidRequest)
        #expect(DemoModelFailure(error: GemmaProviderError.invalidResponse) == .invalidResponse)
        #expect(DemoModelFailure(error: GemmaProviderError.httpStatus(404)) == .httpStatus(404))
    }

    @Test("Transport and unexpected failures are classified without their descriptions")
    func nonProviderFailuresAreClassified() {
        #expect(DemoModelFailure(error: URLError(.notConnectedToInternet)) == .transport(-1009))
        #expect(DemoModelFailure(error: DemoTestError.unexpected) == .unexpected)
    }
}

private actor CapturingDemoProvider: RecoveryModelProviding {
    private let advice: RecoveryAdvice
    private(set) var request: RecoveryModelRequest?

    init(advice: RecoveryAdvice) {
        self.advice = advice
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        self.request = request
        return advice
    }
}

private enum DemoTestError: Error {
    case unexpected
}
