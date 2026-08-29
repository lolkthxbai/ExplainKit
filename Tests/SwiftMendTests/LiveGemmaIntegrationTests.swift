import Foundation
import SwiftMend
import Testing
@testable import SwiftMendDemo

extension Tag {
    @Tag static var liveGemma: Self
}

struct LiveGemmaIntegrationTests {
    @Test(
        "Both live scenarios return only approved Gemma actions",
        .enabled(if: LiveGemmaTestConfiguration.isEnabled),
        .tags(.liveGemma),
        .timeLimit(.minutes(1))
    )
    func liveScenariosReturnApprovedActions() async throws {
        let apiKey = try #require(LiveGemmaTestConfiguration.apiKey)
        let provider = DiagnosticRecoveryModelProvider(
            wrapping: try GemmaRecoveryModelProvider(apiKey: apiKey)
        )
        let source = OSLogDiagnosticSource(
            subsystem: "com.lolkthxbai.SwiftMendDemo",
            category: "recovery"
        )

        for scenario in [DemoScenario.liveGemmaStorePickup, .liveGemmaPhotoUpload] {
            let outcome = await scenario.run(using: source, modelProvider: provider)
            let approvedIDs = Set(scenario.approvedModelActions.map(\.id))

            #expect(outcome.source == .model)
            #expect(outcome.advice.actions.isEmpty == false)
            #expect(outcome.advice.actions.allSatisfy { approvedIDs.contains($0.id) })
            if [
                outcome.snapshot.domain,
                outcome.snapshot.message,
                outcome.snapshot.debugDescription
            ].contains(where: { $0.contains(apiKey) }) {
                Issue.record("The API key appeared in a diagnostic field.")
            }
        }
    }
}

private enum LiveGemmaTestConfiguration {
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
