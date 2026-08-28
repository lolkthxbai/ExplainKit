import SwiftUI

struct DemoIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn generic failures into useful next steps")
                .font(.title2.bold())
            Text("Each scenario writes a privacy-reviewed diagnostic through Apple Logging. The first two stay deterministic; the third can call hosted Gemma when GEMINI_API_KEY is available.")
                .foregroundStyle(.secondary)
        }
    }
}
