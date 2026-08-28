import Foundation
import OSLog

/// Captures a caught error at the same boundary where it is written to Apple unified logging.
public struct OSLogDiagnosticSource: Sendable {
    private let logger: Logger

    public init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    /// Writes developer-reviewed diagnostics to unified logging and returns the matching snapshot.
    ///
    /// Only pass values that are safe to display in Console and send to a configured model provider.
    public func capture(
        error: any Error,
        safeMessage: String,
        safeDebugDescription: String = "",
        context: RecoveryContext
    ) -> ErrorSnapshot {
        let error = error as NSError

        logger.error(
            "SwiftMend captured error domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public) feature=\(context.feature, privacy: .public) message=\(safeMessage, privacy: .public) debug=\(safeDebugDescription, privacy: .public)"
        )

        return ErrorSnapshot(
            error: error,
            safeMessage: safeMessage,
            safeDebugDescription: safeDebugDescription
        )
    }
}
