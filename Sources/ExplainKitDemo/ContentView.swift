import ExplainKit
import SwiftUI

struct ContentView: View {
    @State private var outcomes: [DemoScenario: DemoOutcome] = [:]

    private let diagnosticSource = OSLogDiagnosticSource(
        subsystem: "com.lolkthxbai.ExplainKitDemo",
        category: "recovery"
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introduction

                    ForEach(DemoScenario.allCases) { scenario in
                        ScenarioCard(
                            scenario: scenario,
                            outcome: outcomes[scenario],
                            run: { run(scenario) }
                        )
                    }
                }
                .padding(24)
            }
            .navigationTitle("ExplainKit Demo")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn generic failures into useful next steps")
                .font(.title2.bold())
            Text("Each scenario writes a privacy-reviewed diagnostic through Apple Logging, then resolves it with deterministic ExplainKit policy.")
                .foregroundStyle(.secondary)
        }
    }

    private func run(_ scenario: DemoScenario) {
        Task {
            outcomes[scenario] = await scenario.run(using: diagnosticSource)
        }
    }
}

private struct ScenarioCard: View {
    let scenario: DemoScenario
    let outcome: DemoOutcome?
    let run: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label(scenario.subtitle, systemImage: scenario.symbol)
                    .foregroundStyle(.secondary)

                if let outcome {
                    result(outcome)
                } else {
                    Text("Run the scenario to compare the original error with ExplainKit’s advice.")
                        .foregroundStyle(.secondary)
                }

                Button("Run Scenario", action: run)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Run \(scenario.title) scenario")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            Text(scenario.title)
                .font(.headline)
        }
    }

    private func result(_ outcome: DemoOutcome) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text("Generic error")
                    .font(.headline)
                Text("ExplainKit advice")
                    .font(.headline)
            }

            Divider()
            Divider()

            GridRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(outcome.snapshot.message)
                    Text("\(outcome.snapshot.domain) · \(outcome.snapshot.code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(outcome.advice.title)
                        .fontWeight(.semibold)
                    Text(outcome.advice.message)
                    ForEach(outcome.advice.actions) { action in
                        Label(action.title, systemImage: "arrow.right.circle")
                            .font(.callout)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 700)
}
