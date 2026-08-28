import SwiftUI

struct OutcomeComparisonView: View {
    let outcome: DemoOutcome

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        if usesCompactLayout {
            VStack(alignment: .leading, spacing: 16) {
                GenericErrorView(snapshot: outcome.snapshot)
                Divider()
                RecoveryAdviceView(outcome: outcome)
            }
        } else {
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    GenericErrorView(snapshot: outcome.snapshot)
                    RecoveryAdviceView(outcome: outcome)
                }
            }
        }
    }

    private var usesCompactLayout: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }
}
