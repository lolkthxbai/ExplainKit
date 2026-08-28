import ExplainKit
import Foundation

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case passwordRejected
    case noInternet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passwordRejected: "Password rejected"
        case .noInternet: "No internet"
        }
    }

    var subtitle: String {
        switch self {
        case .passwordRejected: "Developer-approved rule"
        case .noInternet: "Local fallback"
        }
    }

    var symbol: String {
        switch self {
        case .passwordRejected: "key.fill"
        case .noInternet: "wifi.slash"
        }
    }

    func run(using source: OSLogDiagnosticSource) async -> DemoOutcome {
        let context = recoveryContext
        let snapshot = source.capture(
            error: error,
            safeMessage: safeMessage,
            safeDebugDescription: safeDebugDescription,
            context: context
        )
        let advice = await recoveryEngine.recover(from: snapshot, context: context)
        return DemoOutcome(snapshot: snapshot, advice: advice)
    }

    private var error: NSError {
        switch self {
        case .passwordRejected:
            NSError(domain: "DemoAuth", code: 1001)
        case .noInternet:
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
    }

    private var safeMessage: String {
        switch self {
        case .passwordRejected: "The password could not be accepted."
        case .noInternet: "The Internet connection appears to be offline."
        }
    }

    private var safeDebugDescription: String {
        switch self {
        case .passwordRejected: "Password policy validation failed."
        case .noInternet: "A network request failed before reaching the service."
        }
    }

    private var recoveryContext: RecoveryContext {
        switch self {
        case .passwordRejected:
            RecoveryContext(
                feature: "account creation",
                attributes: ["minimumPasswordLength": "12"]
            )
        case .noInternet:
            RecoveryContext(feature: "profile sync")
        }
    }

    private var recoveryEngine: RecoveryEngine {
        switch self {
        case .passwordRejected:
            RecoveryEngine(
                rules: [
                    RecoveryRule(
                        id: "password-policy",
                        matcher: ErrorMatcher(
                            domains: ["DemoAuth"],
                            codes: [1001],
                            requiredAttributes: ["minimumPasswordLength": "12"]
                        ),
                        advice: RecoveryAdvice(
                            title: "Choose a stronger password",
                            message: "Use at least 12 characters and avoid personal information.",
                            actions: [RecoveryAction(id: "edit-password", title: "Edit Password")]
                        )
                    )
                ],
                fallbackAdvice: genericFallback
            )
        case .noInternet:
            RecoveryEngine(
                fallbackAdvice: RecoveryAdvice(
                    title: "Reconnect to the internet",
                    message: "Check Wi-Fi or cellular data, then retry when your device is online.",
                    actions: [
                        RecoveryAction(id: "check-wifi", title: "Check Wi-Fi"),
                        RecoveryAction(id: "check-cellular", title: "Check Cellular Data"),
                        RecoveryAction(id: "retry", title: "Try Again")
                    ]
                )
            )
        }
    }

    private var genericFallback: RecoveryAdvice {
        RecoveryAdvice(
            title: "Try again",
            message: "The request could not be completed.",
            actions: [RecoveryAction(id: "retry", title: "Try Again")]
        )
    }
}

struct DemoOutcome: Equatable, Sendable {
    let snapshot: ErrorSnapshot
    let advice: RecoveryAdvice
}
