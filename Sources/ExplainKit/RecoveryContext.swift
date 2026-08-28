/// App-owned facts that can make recovery advice more specific.
public struct RecoveryContext: Codable, Equatable, Sendable {
    public let feature: String
    public let attributes: [String: String]

    public init(feature: String, attributes: [String: String] = [:]) {
        self.feature = feature
        self.attributes = attributes
    }
}
