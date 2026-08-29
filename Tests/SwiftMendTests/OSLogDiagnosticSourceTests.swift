import Foundation
import OSLog
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

    @Test("Unified logging excludes the original NSError description")
    func captureDoesNotLogUnsafeNSErrorDescription() async throws {
        let subsystem = "com.example.SwiftMendTests.\(UUID().uuidString)"
        let source = OSLogDiagnosticSource(
            subsystem: subsystem,
            category: "privacy"
        )
        let unsafeSentinel = "unsafe-diagnostic-sentinel"
        let safeMessage = "The request could not be completed."
        let startDate = Date()

        _ = source.capture(
            error: NSError(
                domain: "DemoPrivacy",
                code: 99,
                userInfo: [NSLocalizedDescriptionKey: unsafeSentinel]
            ),
            safeMessage: safeMessage,
            safeDebugDescription: "A reviewed test diagnostic.",
            context: RecoveryContext(feature: "privacy test")
        )

        try await Task.sleep(for: .milliseconds(250))
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: startDate))
        let messages = entries.compactMap { entry -> String? in
            guard let logEntry = entry as? OSLogEntryLog,
                  logEntry.subsystem == subsystem else {
                return nil
            }
            return logEntry.composedMessage
        }

        #expect(messages.contains { $0.contains(safeMessage) })
        #expect(messages.contains { $0.contains(unsafeSentinel) } == false)
    }
}
