import Foundation

/// A safe, serializable representation of an error caught by an app.
public struct ErrorSnapshot: Codable, Equatable, Sendable {
    public let domain: String
    public let code: Int
    public let message: String
    public let debugDescription: String

    public init(domain: String, code: Int, message: String, debugDescription: String = "") {
        self.domain = domain
        self.code = code
        self.message = message
        self.debugDescription = debugDescription
    }

    public init(
        error: any Error,
        safeMessage: String,
        safeDebugDescription: String = ""
    ) {
        let error = error as NSError
        self.init(
            domain: error.domain,
            code: error.code,
            message: safeMessage,
            debugDescription: safeDebugDescription
        )
    }
}
