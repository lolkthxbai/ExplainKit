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
                VStack(alignment: .leading, spacing: 20) {
                    introduction

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

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn generic failures into useful next steps")
                .font(.title2.bold())
            Text("Each scenario writes a privacy-reviewed diagnostic through Apple Logging. The first two stay deterministic; the third can call hosted Gemma when GEMINI_API_KEY is available.")
                .foregroundStyle(.secondary)
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

private struct ScenarioCard: View {
    let scenario: DemoScenario
    let outcome: DemoOutcome?
    let isRunning: Bool
    let isLiveGemmaConfigured: Bool
    let run: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label(scenario.subtitle, systemImage: scenario.symbol)
                    .foregroundStyle(.secondary)

                if scenario == .liveGemma {
                    Label(
                        isLiveGemmaConfigured ? "GEMINI_API_KEY available" : "GEMINI_API_KEY missing — local fallback will be used",
                        systemImage: isLiveGemmaConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isLiveGemmaConfigured ? .green : .orange)
                    .font(.callout)
                }

                if let outcome {
                    result(outcome)
                } else {
                    Text("Run the scenario to compare the original error with SwiftMend’s advice.")
                        .foregroundStyle(.secondary)
                }

                Button(action: run) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Run Scenario")
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

    private func result(_ outcome: DemoOutcome) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text("Generic error")
                    .font(.headline)
                Text("SwiftMend advice")
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
                    Label(outcome.source.displayName, systemImage: outcome.source.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(outcome.source.color)
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
    ContentView(environment: [:])
        .frame(width: 800, height: 700)
}

private extension RecoveryAdviceSource {
    var displayName: String {
        switch self {
        case .developerRule(let id): "Developer rule · \(id)"
        case .model: "Gemma"
        case .fallback: "Local fallback"
        }
    }

    var symbol: String {
        switch self {
        case .developerRule: "checkmark.shield.fill"
        case .model: "sparkles"
        case .fallback: "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .developerRule: .blue
        case .model: .purple
        case .fallback: .orange
        }
    }
}
