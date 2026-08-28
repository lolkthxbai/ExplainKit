import ExplainKit
import OSLog

enum DemoResolutionLogger {
    private static let logger = Logger(
        subsystem: "com.lolkthxbai.ExplainKitDemo",
        category: "recovery"
    )

    static func record(scenario: DemoScenario, source: RecoveryAdviceSource) {
        logger.notice(
            "ExplainKit resolved scenario=\(scenario.rawValue, privacy: .public) source=\(source.logName, privacy: .public)"
        )
    }
}

private extension RecoveryAdviceSource {
    var logName: String {
        switch self {
        case .developerRule: "developer-rule"
        case .model: "gemma"
        case .fallback: "local-fallback"
        }
    }
}
