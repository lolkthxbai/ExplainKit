import ExplainKit
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
    }

    @Test("Offline scenario resolves through local fallback")
    func offlineScenarioUsesFallback() async {
        let outcome = await DemoScenario.noInternet.run(using: source)

        #expect(outcome.snapshot.code == -1009)
        #expect(outcome.advice.title == "Reconnect to the internet")
        #expect(outcome.advice.actions.count == 3)
    }
}
