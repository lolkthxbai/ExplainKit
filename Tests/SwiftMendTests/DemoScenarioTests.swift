import Foundation
import SwiftMend
import Testing
@testable import SwiftMendDemo

struct DemoScenarioTests {
    private let source = OSLogDiagnosticSource(
        subsystem: "com.example.SwiftMendTests",
        category: "demo"
    )

    @Test("Example groups and scenarios have an explicit presentation order")
    func groupsHaveExactOrder() {
        #expect(DemoExampleGroup.allCases == [.gemini, .onDeviceGemma, .deterministic])
        #expect(DemoExampleGroup.gemini.scenarios == [
            .checkoutInventoryChanged,
            .storePickupUnavailable
        ])
        #expect(DemoExampleGroup.onDeviceGemma.scenarios == [
            .photoUploadTooLarge,
            .deviceStorageFull
        ])
        #expect(DemoExampleGroup.deterministic.scenarios == [
            .noInternet,
            .invalidModelResponse,
            .passwordRejected
        ])
        #expect(DemoExampleGroup.allCases.flatMap(\.scenarios) == DemoScenario.allCases)
    }

    @Test("Every scenario exposes truthful presentation and routing metadata")
    func scenarioMetadataIsExact() {
        #expect(DemoScenario.checkoutInventoryChanged.metadata == DemoScenarioMetadata(
            group: .gemini,
            exampleType: .geminiModel,
            errorType: "Checkout error",
            symbol: "cart.badge.exclamationmark",
            fallbackTrigger: nil,
            modelRoute: .gemini
        ))
        #expect(DemoScenario.storePickupUnavailable.metadata.group == .gemini)
        #expect(DemoScenario.storePickupUnavailable.errorType == "Pickup availability error")
        #expect(DemoScenario.storePickupUnavailable.modelRoute == .gemini)
        #expect(DemoScenario.photoUploadTooLarge.metadata.group == .onDeviceGemma)
        #expect(DemoScenario.photoUploadTooLarge.modelRoute == .localGemma)
        #expect(DemoScenario.deviceStorageFull.errorType == "Storage error")
        #expect(DemoScenario.deviceStorageFull.modelRoute == .localGemma)
        #expect(DemoScenario.noInternet.fallbackTrigger == .noInternet)
        #expect(DemoScenario.noInternet.errorType == "Connectivity error")
        #expect(DemoScenario.noInternet.modelRoute == .simulatedUnavailable)
        #expect(DemoScenario.invalidModelResponse.fallbackTrigger == .invalidModelResponse)
        #expect(DemoScenario.invalidModelResponse.errorType == "Sync error")
        #expect(DemoScenario.invalidModelResponse.modelRoute == .simulatedInvalidResponse)
        #expect(DemoScenario.passwordRejected.modelRoute == .none)
    }

    @Test(
        "Configured model scenarios preserve their route and canonical action catalog",
        arguments: [
            DemoScenario.checkoutInventoryChanged,
            .storePickupUnavailable,
            .photoUploadTooLarge,
            .deviceStorageFull
        ]
    )
    func configuredModelScenariosUseCanonicalActions(
        scenario: DemoScenario
    ) async throws {
        let approvedAction = try #require(scenario.approvedModelActions.first)
        let provider = CapturingDemoProvider(
            advice: RecoveryAdvice(
                title: "Model explanation",
                message: "Choose one of the approved recovery options.",
                actions: [
                    RecoveryAction(
                        id: approvedAction.id,
                        title: "Model changed this title"
                    )
                ]
            )
        )

        let outcome = await scenario.run(using: source, modelProvider: provider)
        let request = try #require(await provider.request)

        #expect(request.approvedActions == scenario.approvedModelActions)
        #expect(outcome.advice.actions == [approvedAction])
        #expect(outcome.source == .model)
        #expect(outcome.providerKind == scenario.modelRoute.expectedProviderKind)
    }

    @Test("Checkout inventory scenario uses code 4002 and approved inventory actions")
    func checkoutInventoryScenarioIsExact() async throws {
        let provider = CapturingDemoProvider(
            advice: RecoveryAdvice(
                title: "Update checkout",
                message: "Choose another available option.",
                actions: [
                    RecoveryAction(
                        id: "choose-in-stock-store",
                        title: "Untrusted title"
                    )
                ]
            )
        )

        let outcome = await DemoScenario.checkoutInventoryChanged.run(
            using: source,
            modelProvider: provider
        )
        let request = try #require(await provider.request)

        #expect(outcome.snapshot.domain == "DemoCheckout")
        #expect(outcome.snapshot.code == 4002)
        #expect(request.context.feature == "checkout")
        #expect(request.approvedActions == [
            RecoveryAction(
                id: "choose-in-stock-store",
                title: "Choose a store with in-stock availability"
            ),
            RecoveryAction(
                id: "choose-different-color",
                title: "Choose a different item color"
            ),
            RecoveryAction(
                id: "notify-when-available",
                title: "Notify me when it is back in stock"
            )
        ])
    }

    @Test("Photo upload sends reviewed size context to on-device Gemma")
    func photoUploadRequestContainsReviewedContext() async throws {
        let scenario = DemoScenario.photoUploadTooLarge
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

    @Test("Storage scenario uses Cocoa code 640 and storage-only actions")
    func storageScenarioIsExact() async throws {
        let scenario = DemoScenario.deviceStorageFull
        let action = try #require(scenario.approvedModelActions.first)
        let provider = CapturingDemoProvider(
            advice: RecoveryAdvice(
                title: "Free up storage",
                message: "Manage storage before downloading.",
                actions: [action]
            )
        )

        let outcome = await scenario.run(using: source, modelProvider: provider)

        #expect(outcome.snapshot.domain == NSCocoaErrorDomain)
        #expect(outcome.snapshot.code == 640)
        #expect(scenario.approvedModelActions == [
            RecoveryAction(id: "manage-storage", title: "Manage device storage"),
            RecoveryAction(id: "cancel-download", title: "Cancel download")
        ])
    }

    @Test(
        "Deterministic failure scenarios ignore configured providers and use fallback",
        arguments: [DemoScenario.noInternet, .invalidModelResponse]
    )
    func deterministicFailuresUseFallback(scenario: DemoScenario) async {
        let unusedProvider = CountingDemoProvider()

        let outcome = await scenario.run(
            using: source,
            modelProvider: unusedProvider
        )

        #expect(await unusedProvider.requestCount == 0)
        #expect(outcome.source == .fallback)
        #expect(outcome.providerKind == .deterministic)
        #expect(outcome.advice.actions.isEmpty == false)
    }

    @Test("Unavailable-provider scenario represents the no-internet error")
    func unavailableProviderScenarioIsExact() async {
        let outcome = await DemoScenario.noInternet.run(using: source)

        #expect(outcome.snapshot.domain == NSURLErrorDomain)
        #expect(outcome.snapshot.code == NSURLErrorNotConnectedToInternet)
        #expect(outcome.advice.title == "Reconnect to the internet")
        #expect(outcome.source == .fallback)
    }

    @Test("Insufficient model output is rejected in favor of deterministic advice")
    func invalidResponseScenarioUsesFallback() async {
        let outcome = await DemoScenario.invalidModelResponse.run(using: source)

        #expect(outcome.snapshot.domain == "DemoService")
        #expect(outcome.snapshot.code == 1514)
        #expect(outcome.snapshot.message == "Changes could not be synchronized.")
        #expect(outcome.advice.title == "Review conflicting changes")
        #expect(outcome.advice.actions.map(\.id) == [
            "review-changes",
            "keep-device-copy",
            "keep-server-copy"
        ])
        #expect(outcome.source == .fallback)
    }

    @Test("Password scenario resolves through its approved rule")
    func passwordScenarioUsesRule() async {
        let outcome = await DemoScenario.passwordRejected.run(using: source)

        #expect(outcome.snapshot.domain == "DemoAuth")
        #expect(outcome.snapshot.code == 1001)
        #expect(outcome.advice.title == "Choose a stronger password")
        #expect(outcome.advice.actions == [
            RecoveryAction(id: "edit-password", title: "Edit password")
        ])
        #expect(outcome.source == .developerRule(id: "password-policy"))
        #expect(outcome.providerKind == .deterministic)
    }

    @Test("Gemini and Gemma provider errors share safe failure categories")
    func providerFailuresAreClassified() {
        #expect(DemoModelFailure(error: GemmaProviderError.invalidConfiguration) == .invalidConfiguration)
        #expect(DemoModelFailure(error: GemmaProviderError.invalidRequest) == .invalidRequest)
        #expect(DemoModelFailure(error: GemmaProviderError.invalidResponse) == .invalidResponse)
        #expect(DemoModelFailure(error: GemmaProviderError.httpStatus(404)) == .httpStatus(404))
        #expect(DemoModelFailure(error: GeminiProviderError.invalidConfiguration) == .invalidConfiguration)
        #expect(DemoModelFailure(error: GeminiProviderError.invalidRequest) == .invalidRequest)
        #expect(DemoModelFailure(error: GeminiProviderError.invalidResponse) == .invalidResponse)
        #expect(DemoModelFailure(error: GeminiProviderError.httpStatus(429)) == .httpStatus(429))
    }

    @Test("Transport and unexpected failures omit error descriptions")
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

private actor CountingDemoProvider: RecoveryModelProviding {
    private(set) var requestCount = 0

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        requestCount += 1
        return RecoveryAdvice(
            title: "Unused",
            message: "This provider should not be called.",
            actions: [RecoveryAction(id: "retry", title: "Try again")]
        )
    }
}

private enum DemoTestError: Error {
    case unexpected
}
