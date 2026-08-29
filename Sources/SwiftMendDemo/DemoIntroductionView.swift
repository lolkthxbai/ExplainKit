import SwiftUI

struct DemoIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn generic failures into useful next steps")
                .font(.title2.bold())
            Text("Each scenario writes a privacy-reviewed diagnostic through Apple Logging. The first two stay deterministic; the last two can call hosted Gemma and only select developer-approved actions.")
                .foregroundStyle(.secondary)
        }
    }
}
