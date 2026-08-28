# SwiftMend iPhone Demo

Open `SwiftMendDemoApp.xcodeproj`, select an iPhone Simulator, and run the `SwiftMendDemoApp` scheme. The app reuses the same tested scenario sources as the macOS Swift package demo and links the local `SwiftMend` library product.

The password and no-internet scenarios are deterministic and require no API key. To use hosted Gemma, copy `Configurations/Secrets.xcconfig.example` to `Configurations/Secrets.xcconfig`, replace the placeholder with your key, and rebuild. `Secrets.xcconfig` is ignored by Git.

The direct key configuration is only for this local proof of concept. A production app should call a developer-controlled backend instead of embedding a provider key in its bundle.
