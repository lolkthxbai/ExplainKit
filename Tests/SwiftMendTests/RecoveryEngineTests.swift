import Foundation
import Testing
@testable import SwiftMend

struct RecoveryEngineTests {
    private let fallback = RecoveryAdvice(
        title: "Try again later",
        message: "The request could not be completed.",
        actions: [RecoveryAction(id: "retry", title: "Try Again")]
    )

    @Test("A matching developer rule takes priority over a model provider")
    func matchingRuleTakesPriority() async {
        let ruleAdvice = RecoveryAdvice(
            title: "Choose a stronger password",
            message: "Use at least 12 characters.",
            actions: [RecoveryAction(id: "edit-password", title: "Edit Password")]
        )
        let modelAdvice = RecoveryAdvice(title: "Model advice", message: "Unused", actions: [])
        let engine = RecoveryEngine(
            rules: [passwordRule(advice: ruleAdvice)],
            fallbackAdvice: fallback,
            modelProvider: MockRecoveryModelProvider(returning: modelAdvice)
        )

        let resolution = await engine.resolve(
            ErrorSnapshot(domain: "Auth", code: 1001, message: "Password rejected"),
            context: RecoveryContext(feature: "sign-up", attributes: ["minimumPasswordLength": "12"])
        )

        #expect(resolution.advice == ruleAdvice)
        #expect(resolution.source == .developerRule(id: "password-rejected"))
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

    @Test("The provider supplies advice when no approved rule matches")
    func providerSuppliesAdviceWhenNoRuleMatches() async {
        let modelAdvice = RecoveryAdvice(
            title: "Check your connection",
            message: "Reconnect to Wi-Fi or cellular data, then try again.",
            actions: [RecoveryAction(id: "open-settings", title: "Open Settings")]
        )
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            modelProvider: MockRecoveryModelProvider(returning: modelAdvice)
        )

        let resolution = await engine.resolve(
            ErrorSnapshot(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, message: "Offline"),
            context: RecoveryContext(feature: "profile sync")
        )

        #expect(resolution.advice == modelAdvice)
        #expect(resolution.source == .model)
    }

    @Test("A provider failure uses local fallback advice")
    func providerFailureUsesFallback() async {
        let engine = RecoveryEngine(
            fallbackAdvice: fallback,
            modelProvider: MockRecoveryModelProvider(failingWith: .unavailable)
        )

        let resolution = await engine.resolve(
            ErrorSnapshot(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, message: "Offline"),
            context: RecoveryContext(feature: "profile sync")
        )

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
