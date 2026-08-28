import Foundation
import Testing
@testable import SwiftMend

struct OSLogDiagnosticSourceTests {
    @Test("Logging capture returns only the developer-reviewed diagnostics")
    func captureReturnsSafeSnapshot() {
        let source = OSLogDiagnosticSource(subsystem: "com.example.SwiftMendTests", category: "authentication")
        let error = NSError(
            domain: "Auth",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "Rejected password: secret-value"]
        )

        let snapshot = source.capture(
            error: error,
            safeMessage: "Password rejected",
            safeDebugDescription: "Password policy validation failed",
            context: RecoveryContext(feature: "sign-up")
        )

        #expect(snapshot.domain == "Auth")
        #expect(snapshot.code == 1001)
        #expect(snapshot.message == "Password rejected")
        #expect(snapshot.debugDescription == "Password policy validation failed")
        #expect(snapshot.message.contains("secret-value") == false)
    }
}
