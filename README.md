# ExplainKit

ExplainKit is a UI-independent recovery SDK for Swift apps. An app catches an
error, adds safe context and developer-approved rules, then presents the
resulting advice in its own interface.

This proof of concept is deterministic: it does not call a hosted AI model.
Its `MockRecoveryModelProvider` makes provider behavior testable while the
recovery engine always prefers developer-approved rules and local fallbacks.

## Install

Add ExplainKit as a Swift Package Manager dependency, then import it where an
error is caught:

```swift
import ExplainKit
```

## Status

The initial package surface and test suite are being established on the
`feat/deterministic-recovery-core` branch. A real model provider is deliberately
out of scope for this proof of concept.
