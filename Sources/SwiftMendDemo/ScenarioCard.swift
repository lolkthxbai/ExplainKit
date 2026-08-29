import SwiftUI

struct ScenarioCard: View {
    let scenario: DemoScenario
    let outcome: DemoOutcome?
    let isRunning: Bool
    let fallbackTrigger: String?
    let run: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                ScenarioDetailsView(
                    scenario: scenario,
                    outcome: outcome,
                    fallbackTrigger: fallbackTrigger
                )

                Button(action: run) {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        }
                        Text(isRunning ? "Running…" : "Run Scenario")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .controlSize(.large)
                .accessibilityLabel(
                    isRunning
                        ? "Running \(scenario.title) scenario"
                        : "Run \(scenario.title) scenario"
                )
                .accessibilityHint(
                    "Captures the generic error and resolves approved recovery guidance."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Label(scenario.title, systemImage: scenario.symbol)
                .font(.title3.weight(.semibold))
        }
    }
}
