enum DemoModelRoute: Equatable, Sendable {
    case gemini
    case localGemma
    case simulatedUnavailable
    case simulatedInvalidResponse
    case none

    var expectedProviderKind: DemoProviderKind {
        switch self {
        case .gemini:
            .gemini
        case .localGemma:
            .localGemma
        case .simulatedUnavailable, .simulatedInvalidResponse, .none:
            .deterministic
        }
    }
}
