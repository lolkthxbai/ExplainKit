import SwiftMend
import Foundation

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case passwordRejected
    case noInternet
    case liveGemmaStorePickup
    case liveGemmaPhotoUpload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passwordRejected: "Password rejected"
        case .noInternet: "No internet"
        case .liveGemmaStorePickup: "Live Gemma: store pickup"
        case .liveGemmaPhotoUpload: "Live Gemma: photo upload"
        }
    }

    var subtitle: String {
        switch self {
        case .passwordRejected: "Developer-approved rule"
        case .noInternet: "Local fallback"
        case .liveGemmaStorePickup, .liveGemmaPhotoUpload:
            "Hosted Gemma · approved actions only"
        }
    }

    var symbol: String {
        switch self {
        case .passwordRejected: "key.fill"
        case .noInternet: "wifi.slash"
        case .liveGemmaStorePickup: "shippingbox.fill"
        case .liveGemmaPhotoUpload: "photo.badge.exclamationmark"
        }
    }

    var usesGemma: Bool {
        switch self {
        case .liveGemmaStorePickup, .liveGemmaPhotoUpload: true
        case .passwordRejected, .noInternet: false
        }
    }

    func run(
        using source: OSLogDiagnosticSource,
        modelProvider: (any RecoveryModelProviding)? = nil
    ) async -> DemoOutcome {
        let context = recoveryContext
        let snapshot = source.capture(
            error: error,
            safeMessage: safeMessage,
            safeDebugDescription: safeDebugDescription,
            context: context
        )
        let resolution = await recoveryEngine(modelProvider: modelProvider).resolve(snapshot, context: context)
        DemoResolutionLogger.record(scenario: self, source: resolution.source)
        return DemoOutcome(
            snapshot: snapshot,
            advice: resolution.advice,
            source: resolution.source
        )
    }

    private var error: NSError {
        switch self {
        case .passwordRejected:
            NSError(domain: "DemoAuth", code: 1001)
        case .noInternet:
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        case .liveGemmaStorePickup:
            NSError(domain: "DemoCheckout", code: 2001)
        case .liveGemmaPhotoUpload:
            NSError(domain: "DemoUpload", code: 3001)
        }
    }

    private var safeMessage: String {
        switch self {
        case .passwordRejected: "The password could not be accepted."
        case .noInternet: "The Internet connection appears to be offline."
        case .liveGemmaStorePickup: "The checkout request could not be completed."
        case .liveGemmaPhotoUpload: "The photo could not be uploaded."
        }
    }

    private var safeDebugDescription: String {
        switch self {
        case .passwordRejected: "Password policy validation failed."
        case .noInternet: "A network request failed before reaching the service."
        case .liveGemmaStorePickup: "The selected delivery option is temporarily unavailable."
        case .liveGemmaPhotoUpload: "The selected photo exceeds the app's upload limit."
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
        case .liveGemmaStorePickup:
            RecoveryContext(
                feature: "checkout",
                attributes: ["deliveryOption": "store pickup"]
            )
        case .liveGemmaPhotoUpload:
            RecoveryContext(
                feature: "profile photo upload",
                attributes: [
                    "fileSizeMB": "18",
                    "maximumFileSizeMB": "10",
                    "fileType": "HEIC"
                ]
            )
        }
    }

    private func recoveryEngine(modelProvider: (any RecoveryModelProviding)?) -> RecoveryEngine {
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
        case .liveGemmaStorePickup:
            RecoveryEngine(
                fallbackAdvice: RecoveryAdvice(
                    title: "Choose another delivery option",
                    message: "Return to checkout, select a different delivery option, and try again.",
                    actions: [
                        RecoveryAction(id: "select-home-delivery", title: "Select Home Delivery"),
                        RecoveryAction(id: "choose-different-store", title: "Choose a Different Store"),
                        RecoveryAction(id: "try-again-later", title: "Try Again Later")
                    ]
                ),
                approvedModelActions: approvedModelActions,
                modelProvider: modelProvider
            )
        case .liveGemmaPhotoUpload:
            RecoveryEngine(
                fallbackAdvice: RecoveryAdvice(
                    title: "Choose a smaller photo",
                    message: "Select a photo under 10 MB, then try again.",
                    actions: [
                        RecoveryAction(id: "choose-smaller-photo", title: "Choose a Smaller Photo"),
                        RecoveryAction(id: "try-again", title: "Try Again")
                    ]
                ),
                approvedModelActions: approvedModelActions,
                modelProvider: modelProvider
            )
        }
    }

    var approvedModelActions: [RecoveryAction] {
        switch self {
        case .liveGemmaStorePickup:
            [
                RecoveryAction(id: "select-home-delivery", title: "Select Home Delivery"),
                RecoveryAction(id: "choose-different-store", title: "Choose a Different Store"),
                RecoveryAction(id: "try-again-later", title: "Try Again Later")
            ]
        case .liveGemmaPhotoUpload:
            [
                RecoveryAction(id: "choose-smaller-photo", title: "Choose a Smaller Photo"),
                RecoveryAction(id: "compress-photo", title: "Compress Photo"),
                RecoveryAction(id: "try-again", title: "Try Again")
            ]
        case .passwordRejected, .noInternet:
            []
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
    let source: RecoveryAdviceSource
}
