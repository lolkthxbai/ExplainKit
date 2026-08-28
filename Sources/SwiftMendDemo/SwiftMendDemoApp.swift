import SwiftUI

@main
struct SwiftMendDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
#if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
#endif
        }
    }
}
