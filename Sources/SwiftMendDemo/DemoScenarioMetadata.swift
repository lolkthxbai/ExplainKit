struct DemoScenarioMetadata: Equatable, Sendable {
    let group: DemoExampleGroup
    let exampleType: DemoExampleType
    let errorType: String
    let symbol: String
    let fallbackTrigger: DemoFallbackTrigger?
    let modelRoute: DemoModelRoute
}

enum DemoExampleType: Equatable, Sendable {
    case geminiModel
    case tunedOnDeviceGemma
    case developerDeterministic

    var displayName: String {
        switch self {
        case .geminiModel:
            "Gemini Model"
        case .tunedOnDeviceGemma:
            "Tuned On-Device Gemma"
        case .developerDeterministic:
            "Developer Deterministic Recovery"
        }
    }
}

enum DemoFallbackTrigger: Equatable, Sendable {
    case noInternet
    case invalidModelResponse

    var displayName: String {
        switch self {
        case .noInternet:
            "Model unavailable · no internet connection"
        case .invalidModelResponse:
            "Model response malformed or insufficient"
        }
    }
}
