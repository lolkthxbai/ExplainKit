# SwiftMend iPhone Demo

Open `SwiftMendDemoApp.xcodeproj`, select an iPhone Simulator, and run the `SwiftMendDemoApp` scheme. The app reuses the same tested scenario sources as the macOS Swift package demo and links the local `SwiftMend` library product.

The demo contains four scenarios:

- Password rejected uses a deterministic developer rule.
- No internet uses deterministic local fallback advice.
- Store pickup unavailable uses hosted Gemma with approved delivery and store actions.
- Photo upload too large uses hosted Gemma with approved photo recovery actions.

Both hosted cards are labeled **Hosted Gemma · approved actions only**. Gemma 4
is the model; the Gemini API is how this demo accesses it. The demo does not use
or claim to use a Gemini model.

To use hosted Gemma, copy `Configurations/Secrets.xcconfig.example` to
`Configurations/Secrets.xcconfig`, replace the placeholder with your key, and
rebuild. `Secrets.xcconfig` is ignored by Git.

Gemma returns an explanation and one to three action IDs. SwiftMend rejects IDs
outside each scenario's catalog and maps accepted IDs back to the developer's
canonical action titles. If the key, network, API, catalog, or response is
unavailable or invalid, the card displays its local fallback instead.

The direct key configuration is only for this local proof of concept. A
production app should call a developer-controlled backend instead of embedding
a provider key in its bundle.
