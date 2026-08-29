enum DemoExampleGroup: String, CaseIterable, Identifiable, Sendable {
    case gemini
    case onDeviceGemma
    case deterministic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemini:
            "Gemini model"
        case .onDeviceGemma:
            "Tuned on-device Gemma"
        case .deterministic:
            "Developer deterministic recovery"
        }
    }

    var scenarios: [DemoScenario] {
        switch self {
        case .gemini:
            [.checkoutInventoryChanged, .storePickupUnavailable]
        case .onDeviceGemma:
            [.photoUploadTooLarge, .deviceStorageFull]
        case .deterministic:
            [.noInternet, .invalidModelResponse, .passwordRejected]
        }
    }
}
