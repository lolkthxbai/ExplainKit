import SwiftUI

extension DemoOutcome {
    var recoverySourceDisplayName: String {
        switch source {
        case .developerRule(let id): "Developer rule · \(id)"
        case .model: "\(providerKind.displayName) · approved actions only"
        case .fallback: "Developer deterministic fallback"
        }
    }

    var recoverySourceSymbol: String {
        switch source {
        case .developerRule: "checkmark.shield.fill"
        case .model: "sparkles"
        case .fallback: "arrow.uturn.backward.circle.fill"
        }
    }

    var recoverySourceColor: Color {
        switch source {
        case .developerRule: .blue
        case .model:
            switch providerKind {
            case .gemini: .blue
            case .localGemma: .green
            case .deterministic: .secondary
            }
        case .fallback: .orange
        }
    }
}
