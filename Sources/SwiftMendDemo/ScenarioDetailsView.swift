import SwiftUI

struct ScenarioDetailsView: View {
    let scenario: DemoScenario
    let outcome: DemoOutcome?
    let fallbackTrigger: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScenarioDetailBlock("Example Type") {
                Text(scenario.exampleType.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Divider()

            ScenarioDetailBlock("Error Type") {
                Text(scenario.errorType)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Divider()

            ScenarioDetailBlock("Generic Output") {
                let snapshot = outcome?.snapshot ?? scenario.genericSnapshot
                Text(snapshot.message)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("\(snapshot.domain) · \(snapshot.code)")
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
            }

            Divider()

            ScenarioDetailBlock("Recovery Source") {
                if let outcome {
                    Label(
                        outcome.recoverySourceDisplayName,
                        systemImage: outcome.recoverySourceSymbol
                    )
                    .font(.body)
                    .foregroundStyle(outcome.recoverySourceColor)
                } else {
                    Label("Not run", systemImage: "circle.dashed")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScenarioDetailBlock("Recovery Description") {
                if let outcome {
                    Text(outcome.advice.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(outcome.advice.message)
                        .font(.body)
                        .foregroundStyle(.primary)
                } else {
                    Text("Run the scenario to resolve reviewed recovery guidance.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScenarioDetailBlock("Suggested Actions") {
                if let outcome {
                    ForEach(Array(outcome.advice.actions.enumerated()), id: \.element.id) { index, action in
                        Text("\(index + 1). \(action.title)")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("Run the scenario to see one to three approved actions.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            if let fallbackTrigger {
                Divider()

                ScenarioDetailBlock("Fallback Trigger") {
                    Label(fallbackTrigger, systemImage: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
