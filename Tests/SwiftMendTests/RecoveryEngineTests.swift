import Foundation
import Testing
@testable import SwiftMend

struct RecoveryEngineTests {
    private let fallback = RecoveryAdvice(
        title: "Try again later",
        message: "The request could not be completed.",
        actions: [RecoveryAction(id: "retry", title: "Try Again")]
    )
    private let approvedActions = [
        RecoveryAction(id: "open-settings", title: "Open Settings"),
        RecoveryAction(id: "retry", title: "Try Again")
    ]

    @Test("A matching developer rule takes priority without calling the provider")
    func matchingRuleTakesPriority() async {
        let ruleAdvice = RecoveryAdvice(
            title: "Choose a stronger password",
            message: "Use at least 12 characters.",
            actions: [RecoveryAction(id: "edit-password", title: "Edit Password")]
        )
        let provider = RecordingRecoveryModelProvider(
            result: .success(
                RecoveryAdvice(
                    title: "Model advice",
                    message: "Unused",
                    actions: [approvedActions[0]]
                )
            )
        )
        let engine = RecoveryEngine(
            rules: [passwordRule(advice: ruleAdvice)],
            fallbackAdvice: fallback,
            approvedModelActions: approvedActions,
            modelProvider: provider
        )

        let resolution = await engine.resolve(
            ErrorSnapshot(domain: "Auth", code: 1001, message: "Password rejected"),
            context: RecoveryContext(feature: "sign-up", attributes: ["minimumPasswordLength": "12"])
        )

        #expect(resolution.advice == ruleAdvice)
        #expect(resolution.source == .developerRule(id: "password-rejected"))
        #expect(await provider.requestCount == 0)
    }

    @Test("A rule requires all of its declared context attributes")
    func ruleRequiresMatchingContext() async {
        let ruleAdvice = RecoveryAdvice(title: "Password rule", message: "Use 12 characters.", actions: [])
        let engine = RecoveryEngine(rules: [passwordRule(advice: ruleAdvice)], fallbackAdvice: fallback)

        let advice = await engine.recover(
            from: ErrorSnapshot(domain: "Auth", code: 1001, message: "Password rejected"),
            context: RecoveryContext(feature: "sign-up", attributes: ["minimumPasswordLength": "8"])
        )

        #expect(advice == fallback)
    }

    @Test("Allowed provider actions are mapped to canonical developer titles")
    func allowedProviderActionsUseCanonicalTitles() async {
        let providerAdvice = RecoveryAdvice(
            title: "Check your connection",
            message: "Reconnect, then try again.",
            actions: [RecoveryAction(id: "open-settings", title: "Model changed this title")]
        )
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            approvedModelActions: approvedActions,
            modelProvider: MockRecoveryModelProvider(returning: providerAdvice)
        )

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice.title == providerAdvice.title)
        #expect(resolution.advice.actions == [approvedActions[0]])
        #expect(resolution.source == .model)
    }

    @Test("An unknown provider action ID uses local fallback advice")
    func unknownProviderActionUsesFallback() async {
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            approvedModelActions: approvedActions,
            modelProvider: MockRecoveryModelProvider(
                returning: RecoveryAdvice(
                    title: "Recover",
                    message: "Choose an option.",
                    actions: [RecoveryAction(id: "not-approved", title: "Not Approved")]
                )
            )
        )

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice == fallback)
        #expect(resolution.source == .fallback)
    }

    @Test("Duplicate provider action IDs use local fallback advice")
    func duplicateProviderActionsUseFallback() async {
        let duplicate = RecoveryAction(id: "retry", title: "Anything")
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            approvedModelActions: approvedActions,
            modelProvider: MockRecoveryModelProvider(
                returning: RecoveryAdvice(
                    title: "Recover",
                    message: "Try the approved action.",
                    actions: [duplicate, duplicate]
                )
            )
        )

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice == fallback)
        #expect(resolution.source == .fallback)
    }

    @Test("An empty approved-action catalog skips the provider")
    func emptyCatalogSkipsProvider() async {
        let provider = RecordingRecoveryModelProvider(
            result: .success(
                RecoveryAdvice(title: "Recover", message: "Try again.", actions: [approvedActions[1]])
            )
        )
        let engine = RecoveryEngine(fallbackAdvice: fallback, modelProvider: provider)

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice == fallback)
        #expect(resolution.source == .fallback)
        #expect(await provider.requestCount == 0)
    }

    @Test("A malformed approved-action catalog skips the provider")
    func malformedCatalogSkipsProvider() async {
        let provider = RecordingRecoveryModelProvider(
            result: .success(
                RecoveryAdvice(title: "Recover", message: "Try again.", actions: [approvedActions[1]])
            )
        )
        let duplicateCatalog = [
            RecoveryAction(id: "retry", title: "Try Again"),
            RecoveryAction(id: "retry", title: "Retry Request")
        ]
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            approvedModelActions: duplicateCatalog,
            modelProvider: provider
        )

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice == fallback)
        #expect(resolution.source == .fallback)
        #expect(await provider.requestCount == 0)
    }

    @Test("A provider failure uses local fallback advice")
    func providerFailureUsesFallback() async {
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            approvedModelActions: approvedActions,
            modelProvider: MockRecoveryModelProvider(failingWith: .unavailable)
        )

        let resolution = await engine.resolve(snapshot, context: context)

        #expect(resolution.advice == fallback)
        #expect(resolution.source == .fallback)
    }

    @Test("Error snapshots retain NSError identity with reviewed diagnostics")
    func errorSnapshotPreservesNSErrorIdentity() {
        let error = NSError(
            domain: "Auth",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "Rejected password: secret-value"]
        )

        let snapshot = ErrorSnapshot(
            error: error,
            safeMessage: "Password rejected",
            safeDebugDescription: "Password policy validation failed"
        )

        #expect(snapshot.domain == "Auth")
        #expect(snapshot.code == 1001)
        #expect(snapshot.message == "Password rejected")
        #expect(snapshot.debugDescription == "Password policy validation failed")
        #expect(snapshot.message.contains("secret-value") == false)
    }

    private var snapshot: ErrorSnapshot {
        ErrorSnapshot(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            message: "Offline"
        )
    }

    private var context: RecoveryContext {
        RecoveryContext(feature: "profile sync")
    }

    private func passwordRule(advice: RecoveryAdvice) -> RecoveryRule {
        RecoveryRule(
            id: "password-rejected",
            matcher: ErrorMatcher(
                domains: ["Auth"],
                codes: [1001],
                messageContains: "password",
                requiredAttributes: ["minimumPasswordLength": "12"]
            ),
            advice: advice
        )
    }
}

private actor RecordingRecoveryModelProvider: RecoveryModelProviding {
    private let result: Result<RecoveryAdvice, RecordingProviderError>
    private(set) var requestCount = 0

    init(result: Result<RecoveryAdvice, RecordingProviderError>) {
        self.result = result
    }

    func recoveryAdvice(for request: RecoveryModelRequest) async throws -> RecoveryAdvice {
        requestCount += 1
        return try result.get()
    }
}

private enum RecordingProviderError: Error {
    case unavailable
}
