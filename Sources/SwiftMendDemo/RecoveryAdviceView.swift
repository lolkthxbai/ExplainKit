import SwiftUI

struct RecoveryAdviceView: View {
    let outcome: DemoOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftMend advice")
                .font(.headline)
            Label(outcome.source.displayName, systemImage: outcome.source.symbol)
                .font(.caption.bold())
                .foregroundStyle(outcome.source.color)
            Text(outcome.advice.title)
                .bold()
            Text(outcome.advice.message)
            ForEach(outcome.advice.actions) { action in
                Label(action.title, systemImage: "arrow.right.circle")
                    .font(.callout)
            }
        }
    }
}
