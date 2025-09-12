import Foundation
import os.log

// Define a typealias for the `OpenKit` and `Session`
// from your OpenKit C SDK to improve readability.
//typealias OpenKitInstance = OPOpenKitInstance
//    ..typealias SessionInstance = OPSessionInstance

// MARK: - `PaymentCrashHandler` Class
/// A custom uncaught exception handler to capture and report crashes
/// using the OpenKit SDK.
class PaymentCrashHandler {

    // Store a reference to the active crash session.
    private static var crashSession: SessionInstance?

    // Store a reference to the original exception handler to allow
    // other handlers to process the crash.
    private var originalHandler: NSUncaughtExceptionHandler?

    // MARK: - Initialization
    /// Initializes the crash handler with the original handler.
    init(originalHandler: NSUnaughtExceptionHandler?) {
        self.originalHandler = originalHandler
    }

    // MARK: - Public API
    /// Registers the custom crash handler.
    /// - Parameter session: The OpenKit session to use for reporting crashes.
    static func register(session: SessionInstance) {
        // Store the session instance
        self.crashSession = session

        // Get the default exception handler
        let originalHandler = NSGetUncaughtExceptionHandler()
        
        // If the default handler is not our custom handler, set it.
        // This prevents multiple registrations of the same handler.
        if originalHandler != unsafeBitCast(PaymentCrashHandler.uncaughtExceptionHandler, to: NSUncaughtExceptionHandler.self) {
            NSSetUncaughtExceptionHandler(PaymentCrashHandler.uncaughtExceptionHandler)
            os_log("PaymentCrashHandler registered successfully.", type: .info)
        }
    }

    // A C-style function that the system will call when a crash occurs.
    private static let uncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
        let stackTrace = exception.callStackSymbols.joined(separator: "\n")
        let description = exception.reason ?? "No reason provided."

        os_log("uncaughtException: This is a log from the PaymentCrashHandler....", type: .info)
        
        // Report the crash using the OpenKit SDK.
        if let session = PaymentCrashHandler.crashSession {
            OPReportCrash(session, exception.name.rawValue, description, stackTrace)
            // Wait for a short duration to ensure the crash report is sent.
            Thread.sleep(forTimeInterval: 2.0)
            os_log("Crash report sent via OpenKit.", type: .info)
        }

        // Pass the exception to the original handler if one exists.
        // This ensures other crash reporting tools (like Firebase Crashlytics) still work.
        let handler = PaymentCrashHandler().originalHandler
        if handler != nil {
            handler!(exception)
        }
        else {
            // If no original handler, terminate the process.
            fatalError("No original handler to call after crash report.")
        }
    }
}
