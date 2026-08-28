import ExplainKit
import Foundation

struct DemoConfiguration: Sendable {
    let gemmaProvider: (any RecoveryModelProviding)?

    var isLiveGemmaConfigured: Bool {
        gemmaProvider != nil
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let apiKey = environment["GEMINI_API_KEY"],
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
