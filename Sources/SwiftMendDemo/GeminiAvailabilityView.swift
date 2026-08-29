import SwiftUI

struct GeminiAvailabilityView: View {
    let isConfigured: Bool

    var body: some View {
        Label(
            isConfigured
                ? "Gemini ready · approved actions only"
                : "Gemini unavailable · deterministic fallback will be used",
            systemImage: isConfigured
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.body)
        .foregroundStyle(isConfigured ? .green : .orange)
        .accessibilityLabel(
            isConfigured
                ? "Gemini is ready and limited to approved actions"
                : "Gemini is unavailable; deterministic fallback will be used"
        )
    }
}
