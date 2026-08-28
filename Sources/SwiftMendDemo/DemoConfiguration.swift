import SwiftMend
import Foundation

struct DemoConfiguration: Sendable {
    let gemmaProvider: (any RecoveryModelProviding)?

    var isLiveGemmaConfigured: Bool {
        gemmaProvider != nil
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleAPIKey: String? = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
    ) {
        let apiKey = environment["GEMINI_API_KEY"] ?? bundleAPIKey
        guard let apiKey,
              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            gemmaProvider = nil
            return
        }

        gemmaProvider = try? DiagnosticRecoveryModelProvider(
            wrapping: GemmaRecoveryModelProvider(apiKey: apiKey)
        )
    }

    init(gemmaProvider: (any RecoveryModelProviding)?) {
        self.gemmaProvider = gemmaProvider
    }
}
