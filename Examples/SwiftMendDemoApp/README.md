# SwiftMend iPhone Demo

Open `SwiftMendDemoApp.xcodeproj`, select an iPhone Simulator or connected
iPhone, and run the `SwiftMendDemoApp` scheme. The app links the local
`SwiftMend` and `SwiftMendLiteRT` products and reuses the package demo's tested
scenario definitions.

## Scenario order and routing

The demo presents seven examples from top to bottom:

1. **Gemini Model**
   - Checkout inventory changed — `DemoCheckout · 4002`
   - Store pickup unavailable — `DemoCheckout · 2001`
2. **Tuned On-Device Gemma**
   - Photo upload too large — `DemoUpload · 3001`, 18 MB versus a 10 MB limit
   - Device storage full — `NSCocoaErrorDomain · 640`
3. **Developer Deterministic Recovery**
   - No internet connection — `NSURLErrorDomain · -1009`
   - Invalid model response — `DemoService · 1514`
   - Password rejected — `DemoAuth · 1001`

The first two scenarios route only to `GeminiRecoveryModelProvider`, whose
default is the `gemini-3.7-flash` Gemini model. The next two route only to the
imported `LocalGemmaRecoveryModelProvider`. The final three demonstrate an
unavailable model, an invalid model response rejected by the engine, and
developer-rule precedence. The package still provides a separate hosted
`GemmaRecoveryModelProvider`, but the seven-example demo does not route a card
to it.

Every card uses the same labels: Example Type, Error Type, Generic Output,
Recovery Source, Recovery Description, Suggested Actions, and, when relevant,
Fallback Trigger. Actions are numbered and always use the developer's canonical
titles.

## Configure Gemini for the proof of concept

Copy `Configurations/Secrets.xcconfig.example` to
`Configurations/Secrets.xcconfig`, replace the placeholder with your current
key, and rebuild. `Secrets.xcconfig` is ignored by Git.

The Gemini provider sends the key only in the `x-goog-api-key` request header.
It requests structured JSON with one to three case-sensitive action IDs drawn
from that scenario's approved catalog. SwiftMend maps accepted IDs back to
canonical `RecoveryAction` values, and `RecoveryEngine` independently validates
the provider result before displaying it.

This key setup is only appropriate for a local proof of concept. A key embedded
in a distributed app can be extracted. A production app should call a
developer-controlled backend that owns the key and forwards only
privacy-reviewed diagnostics.

## Import the tuned on-device model

SwiftMend does not bundle or download the licensed model. Obtain the exact
fine-tuned `model.litertlm` artifact separately and make it available to the
demo through the Files picker.

1. Choose **Import Tuned Model** in the app and select `model.litertlm`.
2. Leave the app open while the status changes from Importing to Loading.
3. Run the two on-device examples only after the status reports Ready.

Import copies through a staging location, checks the package-pinned byte size
and SHA-256 digest before activation, and stores the accepted artifact under
the app's Application Support directory. The stored model is excluded from
device backups. Later launches restore the installed artifact and reuse one
loaded provider instead of asking for another import.

If the model is missing, has the wrong size or checksum, cannot load, or fails
inference, the affected card uses its reviewed deterministic fallback and does
not label that advice as Gemma-generated.

## Logging and fallback safety

Each run records only a privacy-reviewed, app-owned diagnostic through Apple
unified logging. SwiftMend does not scrape arbitrary OS logs, and the demo does
not log API keys, prompts, or unsafe diagnostic values.

The no-internet scenario deliberately simulates provider unavailability. The
sync scenario deliberately returns an invalid provider result, proving that
engine-level validation selects the local fallback. The password scenario
matches a developer rule before any provider can run. Missing configuration,
network and API failures, malformed responses, and rejected action catalogs all
resolve to reviewed local advice.
