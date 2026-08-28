# ExplainKit

ExplainKit is a UI-independent recovery SDK for Swift apps. It turns caught
errors, privacy-reviewed diagnostics, and developer-approved policy into clear
next steps the host app can present to its users.

The recovery engine always prefers matching developer rules. If no rule
matches, it asks an optional model provider and falls back to local advice when
the provider is absent or unavailable.

## Install

Add ExplainKit as a Swift Package Manager dependency, then import it where an
error is caught:

```swift
import ExplainKit
```

## Integration

Capture an error through Apple unified logging, then pass the same sanitized
snapshot to the recovery engine:

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

The included SwiftUI demo is a macOS executable with two deterministic flows:

- Password rejected resolves through a developer-approved rule.
- No internet resolves through local fallback advice.

Run it from the repository root:

```shell
swift run ExplainKitDemo
```

Select **Run Scenario** to compare the original generic error with the recovery
guidance. Each run also writes its reviewed diagnostic to Apple unified logging
under subsystem `com.lolkthxbai.ExplainKitDemo` and category `recovery`.

The demo deliberately stays offline and deterministic. It does not read an API
key or call Gemma.

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
