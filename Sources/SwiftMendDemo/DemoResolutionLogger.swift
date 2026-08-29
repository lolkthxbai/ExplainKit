import SwiftMend
import OSLog

enum DemoResolutionLogger {
    private static let logger = Logger(
        subsystem: "com.lolkthxbai.SwiftMendDemo",
        category: "recovery"
    )

    static func record(scenario: DemoScenario, source: RecoveryAdviceSource) {
        logger.notice(
            "SwiftMend resolved scenario=\(scenario.rawValue, privacy: .public) source=\(source.logName, privacy: .public)"
        )
    }

    static func record(modelFailure: DemoModelFailure) {
        switch modelFailure {
        case .invalidConfiguration:
            logger.error("Gemma request failed kind=invalid-configuration")
        case .invalidRequest:
            logger.error("Gemma request failed kind=invalid-request")
        case .invalidResponse:
            logger.error("Gemma request failed kind=invalid-response")
        case .httpStatus(let statusCode):
            logger.error("Gemma request failed kind=http-status code=\(statusCode, privacy: .public)")
        case .transport(let errorCode):
            logger.error("Gemma request failed kind=transport code=\(errorCode, privacy: .public)")
        case .unexpected:
            logger.error("Gemma request failed kind=unexpected")
        }
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
