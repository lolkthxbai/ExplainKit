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

## Development

Build and test the package with:

```shell
swift build
swift test
```
