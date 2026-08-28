import SwiftMend
import SwiftUI

struct ContentView: View {
    @State private var outcomes: [DemoScenario: DemoOutcome] = [:]
    @State private var runningScenarios: Set<DemoScenario> = []

    private let diagnosticSource = OSLogDiagnosticSource(
        subsystem: "com.lolkthxbai.SwiftMendDemo",
        category: "recovery"
    )
    private let configuration: DemoConfiguration

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        configuration = DemoConfiguration(environment: environment)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    DemoIntroductionView()

                    ForEach(DemoScenario.allCases) { scenario in
                        ScenarioCard(
                            scenario: scenario,
                            outcome: outcomes[scenario],
                            isRunning: runningScenarios.contains(scenario),
                            isLiveGemmaConfigured: configuration.isLiveGemmaConfigured,
                            run: { run(scenario) }
                        )
                    }
                }
                .padding(24)
            }
            .navigationTitle("SwiftMend Demo")
        }
    }

    private func run(_ scenario: DemoScenario) {
        guard runningScenarios.contains(scenario) == false else { return }
        runningScenarios.insert(scenario)

        Task { @MainActor in
            let outcome = await scenario.run(
                using: diagnosticSource,
                modelProvider: scenario == .liveGemma ? configuration.gemmaProvider : nil
            )
            guard Task.isCancelled == false else {
                runningScenarios.remove(scenario)
                return
            }
            outcomes[scenario] = outcome
            runningScenarios.remove(scenario)
        }
    }
}

#Preview {
    ContentView(environment: [:])
#if os(macOS)
        .frame(width: 800, height: 700)
#endif
}
