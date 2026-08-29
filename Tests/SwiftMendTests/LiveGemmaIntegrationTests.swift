import Foundation
import OSLog
import SwiftMend
import Testing
@testable import SwiftMendDemo

extension Tag {
    @Tag static var liveGemini: Self
}

struct LiveModelIntegrationTests {
    private let source = OSLogDiagnosticSource(
        subsystem: "com.lolkthxbai.SwiftMendDemo",
        category: "recovery"
    )

    @Test(
        "Both Gemini scenarios return only canonical approved actions",
        .enabled(if: LiveGeminiTestConfiguration.isEnabled),
        .tags(.liveGemini),
        .timeLimit(.minutes(2))
    )
    func liveGeminiScenariosReturnApprovedActions() async throws {
        let apiKey = try #require(LiveGeminiTestConfiguration.apiKey)
        let provider = DiagnosticRecoveryModelProvider(
            wrapping: try GeminiRecoveryModelProvider(apiKey: apiKey),
            providerKind: .gemini
        )
        let logStart = Date()

        #expect(LiveGeminiTestConfiguration.scenarios == [
            .checkoutInventoryChanged,
            .storePickupUnavailable
        ])

        for scenario in LiveGeminiTestConfiguration.scenarios {
            let outcome = await scenario.run(using: source, modelProvider: provider)
            let approvedActions = scenario.approvedModelActions

            #expect(scenario.modelRoute == .gemini)
            #expect(outcome.source == .model)
            #expect(outcome.providerKind == .gemini)
            #expect((1...3).contains(outcome.advice.actions.count))

            for action in outcome.advice.actions {
                let canonicalAction = try #require(
                    approvedActions.first { $0.id == action.id },
                    "Gemini selected an action outside the scenario catalog."
                )
                #expect(
                    action == canonicalAction,
                    "Displayed actions must use the developer-provided identifier and title."
                )
            }

            verifySecretIsAbsent(from: outcome, apiKey: apiKey)
        }

        try await Task.sleep(for: .milliseconds(250))
        let messages = try demoLogMessages(since: logStart)
        #expect(messages.isEmpty == false, "Expected the live run to emit demo diagnostics.")
        #expect(
            messages.contains { $0.contains(apiKey) } == false,
            "The API key must never appear in SwiftMend demo logs."
        )
    }

    @Test(
        "On-device Gemma scenarios use reviewed fallback when the model is unavailable",
        arguments: [DemoScenario.photoUploadTooLarge, .deviceStorageFull]
    )
    func localGemmaScenariosFallBackWithoutProvider(
        scenario: DemoScenario
    ) async {
        let outcome = await scenario.run(using: source, modelProvider: nil)

        #expect(scenario.modelRoute == .localGemma)
        #expect(outcome.source == .fallback)
        #expect(outcome.providerKind == .deterministic)
        #expect(outcome.advice.actions == scenario.approvedModelActions)
    }

    private func verifySecretIsAbsent(
        from outcome: DemoOutcome,
        apiKey: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let displayedAndDiagnosticValues = [
            outcome.snapshot.domain,
            outcome.snapshot.message,
            outcome.snapshot.debugDescription,
            outcome.advice.title,
            outcome.advice.message,
            outcome.providerKind.displayName
        ] + outcome.advice.actions.flatMap { [$0.id, $0.title] }

        #expect(
            displayedAndDiagnosticValues.contains { $0.contains(apiKey) } == false,
            "The API key must not reach diagnostics or displayed recovery advice.",
            sourceLocation: sourceLocation
        )
    }

    private func demoLogMessages(since startDate: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: startDate)

        return try store.getEntries(at: position).compactMap { entry in
            guard let entry = entry as? OSLogEntryLog,
                  entry.subsystem == "com.lolkthxbai.SwiftMendDemo" else {
                return nil
            }
            return entry.composedMessage
        }
    }
}

private enum LiveGeminiTestConfiguration {
    static let scenarios: [DemoScenario] = [
        .checkoutInventoryChanged,
        .storePickupUnavailable
    ]

    static var apiKey: String? {
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return apiKey
    }

    static var isEnabled: Bool {
        apiKey != nil
    }
}
