import SwiftMend
import OSLog

enum DemoResolutionLogger {
    private static let logger = Logger(
        subsystem: "com.lolkthxbai.SwiftMendDemo",
        category: "recovery"
    )

    static func record(
        scenario: DemoScenario,
        source: RecoveryAdviceSource,
        providerKind: DemoProviderKind
    ) {
        logger.notice(
            "SwiftMend resolved scenario=\(scenario.rawValue, privacy: .public) source=\(source.logName, privacy: .public) provider=\(providerKind.logName, privacy: .public)"
        )
    }

    static func record(
        modelFailure: DemoModelFailure,
        providerKind: DemoProviderKind
    ) {
        switch modelFailure {
        case .invalidConfiguration:
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=invalid-configuration"
            )
        case .invalidRequest:
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=invalid-request"
            )
        case .invalidResponse:
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=invalid-response"
            )
        case .httpStatus(let statusCode):
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=http-status code=\(statusCode, privacy: .public)"
            )
        case .transport(let errorCode):
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=transport code=\(errorCode, privacy: .public)"
            )
        case .unexpected:
            logger.error(
                "Model request failed provider=\(providerKind.logName, privacy: .public) kind=unexpected"
            )
        }
    }
}

private extension RecoveryAdviceSource {
    var logName: String {
        switch self {
        case .developerRule: "developer-rule"
        case .model: "model"
        case .fallback: "developer-fallback"
        }
    }
}
