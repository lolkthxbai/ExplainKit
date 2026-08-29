import SwiftMend
import Foundation

struct DemoConfiguration: Sendable {
    let geminiProvider: (any RecoveryModelProviding)?

    var isGeminiConfigured: Bool {
        geminiProvider != nil
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleAPIKey: String? = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
    ) {
        let apiKey = environment["GEMINI_API_KEY"] ?? bundleAPIKey
        guard let apiKey,
              apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            geminiProvider = nil
            return
        }

        geminiProvider = try? DiagnosticRecoveryModelProvider(
            wrapping: GeminiRecoveryModelProvider(apiKey: apiKey),
            providerKind: .gemini
        )
    }

    init(geminiProvider: (any RecoveryModelProviding)?) {
        self.geminiProvider = geminiProvider
    }
}
