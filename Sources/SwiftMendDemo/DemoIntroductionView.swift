import SwiftUI

struct DemoIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn generic failures into useful next steps")
                .font(.title2.bold())
            Text("Each example captures a privacy-reviewed diagnostic through Apple Logging, then uses Gemini, tuned on-device Gemma, or developer-reviewed deterministic recovery.")
                .foregroundStyle(.secondary)
        }
    }
}
