import SwiftUI

struct ScenarioCard: View {
    let scenario: DemoScenario
    let outcome: DemoOutcome?
    let isRunning: Bool
    let isGemmaConfigured: Bool
    let run: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label(scenario.subtitle, systemImage: scenario.symbol)
                    .foregroundStyle(.secondary)

                if scenario.usesGemma {
                    Label(
                        isGemmaConfigured ? "GEMINI_API_KEY available" : "GEMINI_API_KEY missing — local fallback will be used",
                        systemImage: isGemmaConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isGemmaConfigured ? .green : .orange)
                    .font(.callout)
                }

                if let outcome {
                    OutcomeComparisonView(outcome: outcome)
                } else {
                    Text("Run the scenario to compare the original error with SwiftMend’s advice.")
                        .foregroundStyle(.secondary)
                }

                Button(action: run) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRunning ? "Running…" : "Run Scenario")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .accessibilityLabel("Run \(scenario.title) scenario")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Text(scenario.title)
                .font(.headline)
        }
    }
}
