import Foundation
import SwiftMend
import Testing
@testable import SwiftMendDemo

@MainActor
struct DemoViewModelTests {
    private let diagnosticSource = OSLogDiagnosticSource(
        subsystem: "com.example.SwiftMendTests",
        category: "view-model"
    )

    @Test("Configuration creates only the Gemini provider used by hosted scenarios")
    func geminiConfigurationIsExplicit() {
        let missingKey = DemoConfiguration(environment: [:], bundleAPIKey: nil)
        let configured = DemoConfiguration(geminiProvider: RecordingModelProvider())

        #expect(missingKey.isGeminiConfigured == false)
        #expect(missingKey.geminiProvider == nil)
        #expect(configured.isGeminiConfigured)
        #expect(configured.geminiProvider != nil)
    }

    @Test("A Gemini scenario stores model advice with canonical actions")
    func geminiScenarioUsesConfiguredProvider() async throws {
        let provider = RecordingModelProvider()
        let viewModel = DemoViewModel(
            configuration: DemoConfiguration(geminiProvider: provider),
            diagnosticSource: diagnosticSource
        )

        await viewModel.run(.checkoutInventoryChanged)
        let outcome = try #require(viewModel.outcomes[.checkoutInventoryChanged])

        #expect(await provider.requestCount == 1)
        #expect(outcome.source == .model)
        #expect(outcome.providerKind == .gemini)
        #expect(outcome.advice.actions == [
            RecoveryAction(
                id: "choose-in-stock-store",
                title: "Choose a store with in-stock availability"
            )
        ])
        #expect(viewModel.isRunning(.checkoutInventoryChanged) == false)
        #expect(viewModel.fallbackTrigger(for: .checkoutInventoryChanged) == nil)
    }

    @Test("A missing Gemini key produces an honestly labeled fallback")
    func missingGeminiUsesFallback() async throws {
        let viewModel = DemoViewModel(
            configuration: DemoConfiguration(geminiProvider: nil),
            diagnosticSource: diagnosticSource
        )

        await viewModel.run(.storePickupUnavailable)
        let outcome = try #require(viewModel.outcomes[.storePickupUnavailable])

        #expect(outcome.source == .fallback)
        #expect(outcome.providerKind == .deterministic)
        #expect(
            viewModel.fallbackTrigger(for: .storePickupUnavailable)
                == "Gemini unavailable · API key missing"
        )
    }

    @Test("A missing local model routes Gemma scenarios to reviewed fallback")
    func missingLocalModelUsesFallback() async throws {
        let viewModel = DemoViewModel(
            configuration: DemoConfiguration(geminiProvider: RecordingModelProvider()),
            diagnosticSource: diagnosticSource
        )

        await viewModel.run(.photoUploadTooLarge)
        let outcome = try #require(viewModel.outcomes[.photoUploadTooLarge])

        #expect(outcome.source == .fallback)
        #expect(outcome.providerKind == .deterministic)
        #expect(
            viewModel.fallbackTrigger(for: .photoUploadTooLarge)
                == "On-device Gemma unavailable · verified model not imported"
        )
    }

    @Test("Deterministic scenarios never receive the configured Gemini provider")
    func deterministicRoutesDoNotCallGemini() async throws {
        let provider = RecordingModelProvider()
        let viewModel = DemoViewModel(
            configuration: DemoConfiguration(geminiProvider: provider),
            diagnosticSource: diagnosticSource
        )

        await viewModel.run(.noInternet)
        await viewModel.run(.passwordRejected)
        let offline = try #require(viewModel.outcomes[.noInternet])
        let password = try #require(viewModel.outcomes[.passwordRejected])

        #expect(await provider.requestCount == 0)
        #expect(offline.source == .fallback)
        #expect(password.source == .developerRule(id: "password-policy"))
        #expect(
            viewModel.fallbackTrigger(for: .noInternet)
                == "Model unavailable · no internet connection"
        )
        #expect(viewModel.fallbackTrigger(for: .passwordRejected) == nil)
    }
}

private actor RecordingModelProvider: RecoveryModelProviding {
    private(set) var requestCount = 0

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        requestCount += 1
        let actions: [RecoveryAction]
        if let action = request.approvedActions.first {
            actions = [RecoveryAction(id: action.id, title: "Untrusted model title")]
        } else {
            actions = []
        }
        return RecoveryAdvice(
            title: "Model recovery",
            message: "Choose a developer-approved recovery action.",
            actions: actions
        )
    }
}
