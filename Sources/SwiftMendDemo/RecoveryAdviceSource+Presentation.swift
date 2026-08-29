import SwiftMend
import SwiftUI

extension RecoveryAdviceSource {
    var displayName: String {
        switch self {
        case .developerRule(let id): "Developer rule · \(id)"
        case .model: "Gemma · approved actions"
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
