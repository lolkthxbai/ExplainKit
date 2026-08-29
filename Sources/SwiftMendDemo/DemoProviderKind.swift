enum DemoProviderKind: Equatable, Sendable {
    case gemini
    case localGemma
    case hostedGemma
    case deterministic

    var displayName: String {
        switch self {
        case .gemini:
            "Gemini model"
        case .localGemma:
            "Gemma · tuned on-device model"
        case .hostedGemma:
            "Hosted Gemma"
        case .deterministic:
            "Developer deterministic"
        }
    }

    var logName: String {
        switch self {
        case .gemini:
            "gemini"
        case .localGemma:
            "local-gemma"
        case .hostedGemma:
            "hosted-gemma"
        case .deterministic:
            "developer-deterministic"
        }
    }
}
