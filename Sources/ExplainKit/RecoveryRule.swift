/// A developer-approved mapping from an error pattern to recovery advice.
public struct RecoveryRule: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let matcher: ErrorMatcher
    public let advice: RecoveryAdvice

    public init(id: String, matcher: ErrorMatcher, advice: RecoveryAdvice) {
        self.id = id
        self.matcher = matcher
        self.advice = advice
    }

    public func matches(_ snapshot: ErrorSnapshot, context: RecoveryContext) -> Bool {
        matcher.matches(snapshot) && matcher.requiredAttributes.allSatisfy { context.attributes[$0.key] == $0.value }
    }
}

/// The error and context values a recovery rule requires.
public struct ErrorMatcher: Codable, Equatable, Sendable {
    public let domains: Set<String>
    public let codes: Set<Int>
    public let messageContains: String?
    public let requiredAttributes: [String: String]

    public init(
        domains: Set<String> = [],
        codes: Set<Int> = [],
        messageContains: String? = nil,
        requiredAttributes: [String: String] = [:]
    ) {
        self.domains = domains
        self.codes = codes
        self.messageContains = messageContains
        self.requiredAttributes = requiredAttributes
    }

    public func matches(_ snapshot: ErrorSnapshot) -> Bool {
        let domainMatches = domains.isEmpty || domains.contains(snapshot.domain)
        let codeMatches = codes.isEmpty || codes.contains(snapshot.code)
        let messageMatches = messageContains.map { phrase in
            snapshot.message.localizedCaseInsensitiveContains(phrase)
                || snapshot.debugDescription.localizedCaseInsensitiveContains(phrase)
        } ?? true
        return domainMatches && codeMatches && messageMatches
    }
}
