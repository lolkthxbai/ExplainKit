import SwiftUI

struct ScenarioDetailBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
