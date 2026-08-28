# SwiftMend

SwiftMend is a UI-independent recovery SDK for Swift apps. It turns caught
errors, privacy-reviewed diagnostics, and developer-approved policy into clear
next steps the host app can present to its users.

The recovery engine always prefers matching developer rules. If no rule
matches, it asks an optional model provider and falls back to local advice when
the provider is absent or unavailable.

## Install

Add SwiftMend as a Swift Package Manager dependency, then import it where an
error is caught:

```swift
import SwiftMend
```

## Integration

Capture an error through [Apple unified logging](https://developer.apple.com/documentation/os/logging),
then pass the same sanitized snapshot to the recovery engine:

```swift
let context = RecoveryContext(
    feature: "account creation",
    attributes: ["minimumPasswordLength": "12"]
)
let diagnostics = OSLogDiagnosticSource(
    subsystem: "com.example.MyApp",
    category: "authentication"
)
let snapshot = diagnostics.capture(
    error: error,
    safeMessage: "The password could not be accepted.",
    safeDebugDescription: "Password policy validation failed.",
    context: context
)
let advice = await engine.recover(from: snapshot, context: context)
```

Only pass strings that are safe to display in Console and share with the
configured model provider. Do not include passwords, tokens, account data, or
raw server responses.

## Demo

The included SwiftUI demo is a macOS executable with three flows:

- Password rejected resolves through a developer-approved rule.
- No internet resolves through local fallback advice.
- Live Gemma sends a sanitized checkout error to the hosted model and falls
  back locally if the key, network, API, or response is unavailable.

For the live scenario, export the key and launch the demo from the same terminal:

```shell
export GEMINI_API_KEY="your-key"
swift run SwiftMendDemo
```

Select **Run Scenario** to compare the original generic error with the recovery
guidance. Each run also writes its reviewed diagnostic to Apple unified logging
under subsystem `com.lolkthxbai.SwiftMendDemo` and category `recovery`.

The UI reports whether `GEMINI_API_KEY` is available without displaying or
logging its value. It also labels every result as a developer rule, Gemma, or
local fallback. The first two scenarios never call the model.

The live scenario sends only this reviewed sample diagnostic to Google:

- Domain and code: `DemoCheckout`, `2001`
- Message: `The checkout request could not be completed.`
- Debug description: `The selected delivery option is temporarily unavailable.`
- Context: checkout with delivery option `store pickup`

## Hosted Gemma provider

`GemmaRecoveryModelProvider` implements `RecoveryModelProviding` through the
[Gemini API](https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api). It uses
`gemma-4-26b-a4b-it` by default and accepts another supported model identifier.

```swift
let provider = try GemmaRecoveryModelProvider(apiKey: apiKey)
let engine = RecoveryEngine(
    rules: approvedRules,
    fallbackAdvice: offlineFallback,
    modelProvider: provider
)
```

The provider sends the API key in the `x-goog-api-key` header, requests one
response, and validates the returned JSON before converting it into
`RecoveryAdvice`. Invalid output and network failures are discarded by
`RecoveryEngine` in favor of local fallback advice.

Embedding an API key in a distributed iOS or macOS app is not secure because it
can be extracted. The direct provider is suitable for this proof of concept;
production apps should call a developer-controlled backend that owns the key.

## Development

Build and test the package with:

```shell
swift build
swift test
```
