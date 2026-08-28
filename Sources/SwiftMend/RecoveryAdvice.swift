/// User-facing guidance chosen by the app's recovery policy.
public struct RecoveryAdvice: Codable, Equatable, Sendable {
    public let title: String
    public let message: String
    public let actions: [RecoveryAction]

    public init(title: String, message: String, actions: [RecoveryAction]) {
        self.title = title
        self.message = message
        self.actions = actions
    }
}

/// A UI-neutral action the host app can render or map to its own behavior.
public struct RecoveryAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
