import Foundation
import SwiftMend

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case checkoutInventoryChanged
    case storePickupUnavailable
    case photoUploadTooLarge
    case deviceStorageFull
    case noInternet
    case invalidModelResponse
    case passwordRejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkoutInventoryChanged:
            "Checkout inventory changed"
        case .storePickupUnavailable:
            "Store pickup unavailable"
        case .photoUploadTooLarge:
            "Photo upload too large"
        case .deviceStorageFull:
            "Device storage full"
        case .noInternet:
            "No internet connection"
        case .invalidModelResponse:
            "Invalid model response"
        case .passwordRejected:
            "Password rejected"
        }
    }

    var subtitle: String { exampleType.displayName }

    var metadata: DemoScenarioMetadata {
        switch self {
        case .checkoutInventoryChanged:
            DemoScenarioMetadata(
                group: .gemini,
                exampleType: .geminiModel,
                errorType: "Checkout error",
                symbol: "cart.badge.exclamationmark",
                fallbackTrigger: nil,
                modelRoute: .gemini
            )
        case .storePickupUnavailable:
            DemoScenarioMetadata(
                group: .gemini,
                exampleType: .geminiModel,
                errorType: "Pickup availability error",
                symbol: "shippingbox.fill",
                fallbackTrigger: nil,
                modelRoute: .gemini
            )
        case .photoUploadTooLarge:
            DemoScenarioMetadata(
                group: .onDeviceGemma,
                exampleType: .tunedOnDeviceGemma,
                errorType: "Upload error",
                symbol: "photo.badge.exclamationmark",
                fallbackTrigger: nil,
                modelRoute: .localGemma
            )
        case .deviceStorageFull:
            DemoScenarioMetadata(
                group: .onDeviceGemma,
                exampleType: .tunedOnDeviceGemma,
                errorType: "Storage error",
                symbol: "internaldrive.fill",
                fallbackTrigger: nil,
                modelRoute: .localGemma
            )
        case .noInternet:
            DemoScenarioMetadata(
                group: .deterministic,
                exampleType: .developerDeterministic,
                errorType: "Connectivity error",
                symbol: "wifi.slash",
                fallbackTrigger: .noInternet,
                modelRoute: .simulatedUnavailable
            )
        case .invalidModelResponse:
            DemoScenarioMetadata(
                group: .deterministic,
                exampleType: .developerDeterministic,
                errorType: "Sync error",
                symbol: "exclamationmark.bubble.fill",
                fallbackTrigger: .invalidModelResponse,
                modelRoute: .simulatedInvalidResponse
            )
        case .passwordRejected:
            DemoScenarioMetadata(
                group: .deterministic,
                exampleType: .developerDeterministic,
                errorType: "Password error",
                symbol: "key.fill",
                fallbackTrigger: nil,
                modelRoute: .none
            )
        }
    }

    var group: DemoExampleGroup { metadata.group }
    var exampleType: DemoExampleType { metadata.exampleType }
    var errorType: String { metadata.errorType }
    var symbol: String { metadata.symbol }
    var fallbackTrigger: DemoFallbackTrigger? { metadata.fallbackTrigger }
    var modelRoute: DemoModelRoute { metadata.modelRoute }
    var genericSnapshot: ErrorSnapshot {
        ErrorSnapshot(
            error: error,
            safeMessage: safeMessage,
            safeDebugDescription: safeDebugDescription
        )
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
        let provider = routedProvider(configuredProvider: modelProvider)
        let resolution = await recoveryEngine(modelProvider: provider).resolve(
            snapshot,
            context: context
        )
        let providerKind = resolvedProviderKind(for: resolution.source)
        DemoResolutionLogger.record(
            scenario: self,
            source: resolution.source,
            providerKind: providerKind
        )
        return DemoOutcome(
            snapshot: snapshot,
            advice: resolution.advice,
            source: resolution.source,
            providerKind: providerKind
        )
    }

    private var error: NSError {
        switch self {
        case .checkoutInventoryChanged:
            NSError(domain: "DemoCheckout", code: 4002)
        case .storePickupUnavailable:
            NSError(domain: "DemoCheckout", code: 2001)
        case .photoUploadTooLarge:
            NSError(domain: "DemoUpload", code: 3001)
        case .deviceStorageFull:
            NSError(domain: NSCocoaErrorDomain, code: 640)
        case .noInternet:
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        case .invalidModelResponse:
            NSError(domain: "DemoService", code: 1514)
        case .passwordRejected:
            NSError(domain: "DemoAuth", code: 1001)
        }
    }

    private var safeMessage: String {
        switch self {
        case .checkoutInventoryChanged, .storePickupUnavailable:
            "The checkout request could not be completed."
        case .photoUploadTooLarge:
            "The photo could not be uploaded."
        case .deviceStorageFull:
            "The file could not be saved."
        case .noInternet:
            "The internet connection appears to be offline."
        case .invalidModelResponse:
            "Changes could not be synchronized."
        case .passwordRejected:
            "The password could not be accepted."
        }
    }

    private var safeDebugDescription: String {
        switch self {
        case .checkoutInventoryChanged:
            "The selected item is no longer available at the current store in the chosen color."
        case .storePickupUnavailable:
            "The selected delivery option is temporarily unavailable."
        case .photoUploadTooLarge:
            "The selected photo exceeds the app's upload limit."
        case .deviceStorageFull:
            "The device has insufficient available storage."
        case .noInternet:
            "A network request failed before reaching the service."
        case .invalidModelResponse:
            "Local and server records changed at the same time."
        case .passwordRejected:
            "Password policy validation failed."
        }
    }

    private var recoveryContext: RecoveryContext {
        switch self {
        case .checkoutInventoryChanged:
            RecoveryContext(
                feature: "checkout",
                attributes: [
                    "inventoryState": "changed",
                    "selection": "store and color"
                ]
            )
        case .storePickupUnavailable:
            RecoveryContext(
                feature: "checkout",
                attributes: ["deliveryOption": "store pickup"]
            )
        case .photoUploadTooLarge:
            RecoveryContext(
                feature: "profile photo upload",
                attributes: [
                    "fileSizeMB": "18",
                    "maximumFileSizeMB": "10",
                    "fileType": "HEIC"
                ]
            )
        case .deviceStorageFull:
            RecoveryContext(feature: "offline download")
        case .noInternet:
            RecoveryContext(feature: "profile sync")
        case .invalidModelResponse:
            RecoveryContext(feature: "profile sync")
        case .passwordRejected:
            RecoveryContext(
                feature: "account creation",
                attributes: ["minimumPasswordLength": "12"]
            )
        }
    }

    private func routedProvider(
        configuredProvider: (any RecoveryModelProviding)?
    ) -> (any RecoveryModelProviding)? {
        switch modelRoute {
        case .gemini, .localGemma:
            configuredProvider
        case .simulatedUnavailable:
            DemoFailureRecoveryModelProvider(failure: .unavailable)
        case .simulatedInvalidResponse:
            DemoFailureRecoveryModelProvider(failure: .invalidResponse)
        case .none:
            nil
        }
    }

    private func resolvedProviderKind(
        for source: RecoveryAdviceSource
    ) -> DemoProviderKind {
        switch source {
        case .model:
            modelRoute.expectedProviderKind
        case .developerRule, .fallback:
            .deterministic
        }
    }

    private func recoveryEngine(
        modelProvider: (any RecoveryModelProviding)?
    ) -> RecoveryEngine {
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
                            actions: [
                                RecoveryAction(id: "edit-password", title: "Edit password")
                            ]
                        )
                    )
                ],
                fallbackAdvice: genericFallback
            )
        case .checkoutInventoryChanged:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Update the item selection",
                    message: "Choose an available store or color, or request an availability notification.",
                    actions: approvedModelActions
                )
            )
        case .storePickupUnavailable:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Choose another delivery option",
                    message: "Select another delivery option or store, then try checkout again.",
                    actions: approvedModelActions
                )
            )
        case .photoUploadTooLarge:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Choose a smaller photo",
                    message: "Select or compress a photo under 10 MB, then try again.",
                    actions: approvedModelActions
                )
            )
        case .deviceStorageFull:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Free up device storage",
                    message: "Manage device storage or cancel the download before trying again.",
                    actions: approvedModelActions
                )
            )
        case .noInternet:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Reconnect to the internet",
                    message: "Check Wi-Fi or cellular data, then retry when the device is online.",
                    actions: approvedModelActions
                )
            )
        case .invalidModelResponse:
            modelEngine(
                modelProvider: modelProvider,
                fallbackAdvice: RecoveryAdvice(
                    title: "Review conflicting changes",
                    message: "Choose which version to keep before synchronizing again.",
                    actions: approvedModelActions
                )
            )
        }
    }

    private func modelEngine(
        modelProvider: (any RecoveryModelProviding)?,
        fallbackAdvice: RecoveryAdvice
    ) -> RecoveryEngine {
        RecoveryEngine(
            fallbackAdvice: fallbackAdvice,
            approvedModelActions: approvedModelActions,
            modelProvider: modelProvider
        )
    }

    var approvedModelActions: [RecoveryAction] {
        switch self {
        case .checkoutInventoryChanged:
            [
                RecoveryAction(
                    id: "choose-in-stock-store",
                    title: "Choose a store with in-stock availability"
                ),
                RecoveryAction(
                    id: "choose-different-color",
                    title: "Choose a different item color"
                ),
                RecoveryAction(
                    id: "notify-when-available",
                    title: "Notify me when it is back in stock"
                )
            ]
        case .storePickupUnavailable:
            [
                RecoveryAction(id: "select-home-delivery", title: "Select home delivery"),
                RecoveryAction(id: "choose-different-store", title: "Choose a different store"),
                RecoveryAction(id: "try-again-later", title: "Try again later")
            ]
        case .photoUploadTooLarge:
            [
                RecoveryAction(id: "choose-smaller-photo", title: "Choose a smaller photo"),
                RecoveryAction(id: "compress-photo", title: "Compress photo"),
                RecoveryAction(id: "try-again", title: "Try again")
            ]
        case .deviceStorageFull:
            [
                RecoveryAction(id: "manage-storage", title: "Manage device storage"),
                RecoveryAction(id: "cancel-download", title: "Cancel download")
            ]
        case .noInternet:
            [
                RecoveryAction(id: "check-wifi", title: "Check Wi-Fi"),
                RecoveryAction(id: "check-cellular", title: "Check cellular data"),
                RecoveryAction(id: "retry", title: "Try again")
            ]
        case .invalidModelResponse:
            [
                RecoveryAction(id: "review-changes", title: "Review changes"),
                RecoveryAction(id: "keep-device-copy", title: "Keep this device’s copy"),
                RecoveryAction(id: "keep-server-copy", title: "Keep server copy")
            ]
        case .passwordRejected:
            []
        }
    }

    private var genericFallback: RecoveryAdvice {
        RecoveryAdvice(
            title: "Try again",
            message: "The request could not be completed.",
            actions: [RecoveryAction(id: "retry", title: "Try again")]
        )
    }
}

struct DemoOutcome: Equatable, Sendable {
    let snapshot: ErrorSnapshot
    let advice: RecoveryAdvice
    let source: RecoveryAdviceSource
    let providerKind: DemoProviderKind
}
