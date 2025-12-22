//
//  CrashReporterKit.swift
//  PaymentLibrary
//
//  Created by Simoes, Igor on 12/09/25.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os.log

final class CrashReporterKit {
    static let shared = CrashReporterKit()
    private let crashLogFile = "crash_log.txt"
    
    // Flag to prevent duplicate crash reports (exception handler + signal handler both firing)
    private static var crashReported = false
    
    // Helper to get device model
    private static var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Unknown"
        #endif
    }

    private init() {}

    // MARK: - Public Setup Method

    func enable() {
        NSSetUncaughtExceptionHandler { exception in
            CrashReporterKit.shared.handle(exception: exception)
        }
        setupSignalHandler()
        // Send any saved crash reports from previous crashes that failed to send
        sendCrashReportIfExists()
    }

    // MARK: - Exception Handling

    private func handle(exception: NSException) {
        // Prevent duplicate crash reports
        guard !Self.crashReported else {
            print("⚠️ CRASH ALREADY REPORTED - Skipping duplicate exception handler")
            return
        }
        Self.crashReported = true
        
        // Log crash occurrence
        print("🔴 CRASH HANDLER CALLED - Exception: \(exception.name.rawValue)")
        
        let stackTrace = exception.callStackSymbols.joined(separator: "\n")
        let errorMessage = exception.reason ?? "unknown"

        let extraAttributes: [String: AnyEncodable] = [
            "crash.class": AnyEncodable(exception.name.rawValue),
            "crash.stackTrace": AnyEncodable(stackTrace),
            "device": AnyEncodable(Self.deviceModel)
        ]
        
        // Get current action context for parentActionId and sessionId
        let actionContext = BusinessEventsClient.shared.getCurrentActionContext()
        let sessionId = BusinessEventsClient.shared.sessionId
        
        // If there's an open action, finish it with CRASH status first
        if let currentAction = actionContext {
            do {
                try BusinessEventsClient.shared.endActionSync(
                    currentAction.id,
                    status: "CRASH",
                    error: errorMessage
                )
            } catch {
                print("❌ Failed to finish open action: \(error)")
            }
        }
        
        // Now send the crash report (parent will be the action we just finished)
        let parentActionId = actionContext?.id
        
        // Write to file for backup FIRST (before attempting send)
        // Save as structured data so we can send identical event on next reboot
        let crashData: [String: Any] = [
            "crash.class": exception.name.rawValue,
            "crash.stackTrace": stackTrace,
            "action.error": errorMessage,
            "parentActionId": parentActionId?.uuidString as Any,
            "sessionId": sessionId as Any
        ]
        writeCrashData(crashData)
        
        // Send crash report synchronously - blocks until complete or times out
        var crashSentSuccessfully = false
        do {
            try BusinessEventsClient.shared.sendCrashReportSync(
                parentActionId: parentActionId,
                sessionId: sessionId,
                error: errorMessage,
                extraAttributes: extraAttributes
            )
            crashSentSuccessfully = true
        } catch {
            print("❌ Failed to send crash report: \(error)")
        }
        
        // Delete saved report only if we successfully sent it
        if crashSentSuccessfully {
            deleteSavedReport()
        }
    }

    // MARK: - Signal Handling

    private func setupSignalHandler() {
        func handleSignal(_ signal: Int32) {
            // Prevent duplicate crash reports (NSException already handled this crash)
            guard !CrashReporterKit.crashReported else {
                print("⚠️ CRASH ALREADY REPORTED - Skipping duplicate signal handler")
                exit(signal)
            }
            CrashReporterKit.crashReported = true
            
            let errorMessage = "App crashed with signal: \(signal)"
            
            // Capture stack trace at crash time
            let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
            
            os_log("🔴 SIGNAL CRASH - Signal: %d, StackTrace: %@", log: OSLog.default, type: .fault, signal, stackTrace)
            print("🔴 SIGNAL CRASH - Signal: \(signal)")
            print("🔴 StackTrace:\n\(stackTrace)")
            
            let extraAttributes: [String: AnyEncodable] = [
                "crash.class": AnyEncodable("Signal"),
                "crash.signal": AnyEncodable(signal),
                "crash.stackTrace": AnyEncodable(stackTrace),
                "device": AnyEncodable(CrashReporterKit.deviceModel)
            ]
            
            // Get current action context for parentActionId and sessionId
            let actionContext = BusinessEventsClient.shared.getCurrentActionContext()
            let sessionId = BusinessEventsClient.shared.sessionId
            
            // If there's an open action, finish it with CRASH status first
            if let currentAction = actionContext {
                do {
                    try BusinessEventsClient.shared.endActionSync(
                        currentAction.id,
                        status: "CRASH",
                        error: errorMessage
                    )
                } catch {
                    print("❌ Failed to finish open action: \(error)")
                }
            }
            
            // Now send the crash report (parent will be the action we just finished)
            let parentActionId = actionContext?.id
            
            // Write to file for backup FIRST
            // Save as structured data so we can send identical event on next reboot
            let crashData: [String: Any] = [
                "crash.class": "Signal",
                "crash.signal": signal,
                "crash.stackTrace": stackTrace,
                "action.error": errorMessage,
                "parentActionId": parentActionId?.uuidString as Any,
                "sessionId": sessionId as Any
            ]
            CrashReporterKit.shared.writeCrashData(crashData)
            
            // Send crash report synchronously - blocks until complete or times out
            var crashSentSuccessfully = false
            do {
                try BusinessEventsClient.shared.sendCrashReportSync(
                    parentActionId: parentActionId,
                    sessionId: sessionId,
                    error: errorMessage,
                    extraAttributes: extraAttributes
                )
                crashSentSuccessfully = true
            } catch {
                print("❌ Failed to send signal crash report: \(error)")
            }
            
            // Delete saved report only if we successfully sent it
            if crashSentSuccessfully {
                CrashReporterKit.shared.deleteSavedReport()
            }
            
            exit(signal)
        }

        signal(SIGABRT) { handleSignal($0) }
        signal(SIGILL) { handleSignal($0) }
        signal(SIGSEGV) { handleSignal($0) }
        signal(SIGFPE) { handleSignal($0) }
        signal(SIGBUS) { handleSignal($0) }
        signal(SIGPIPE) { handleSignal($0) }
    }

    // MARK: - Report Crash Method

    static func reportCrash(error: Error, stackTrace: String? = nil) {
        let errorMessage = error.localizedDescription
        let trace = stackTrace ?? Thread.callStackSymbols.joined(separator: "\n")
        
        let extraAttributes: [String: AnyEncodable] = [
            "crash.class": AnyEncodable(String(describing: type(of: error))),
            "crash.stackTrace": AnyEncodable(trace),
            "device": AnyEncodable(deviceModel)
        ]
        
        // Get current action context for parentActionId and sessionId
        let actionContext = BusinessEventsClient.shared.getCurrentActionContext()
        let sessionId = BusinessEventsClient.shared.sessionId
        
        // If there's an open action, finish it with CRASH status first
        if let currentAction = actionContext {
            do {
                try BusinessEventsClient.shared.endActionSync(
                    currentAction.id,
                    status: "CRASH",
                    error: errorMessage
                )
            } catch {
                print("❌ Failed to finish open action: \(error)")
            }
        }
        
        // Now send the crash report (parent will be the action we just finished)
        let parentActionId = actionContext?.id
        
        // Send crash report synchronously - blocks until complete or times out
        do {
            try BusinessEventsClient.shared.sendCrashReportSync(
                parentActionId: parentActionId,
                sessionId: sessionId,
                error: errorMessage,
                extraAttributes: extraAttributes
            )
        } catch {
            print("❌ Failed to send manual crash report: \(error)")
        }
    }

    // MARK: - Save Report

    private func writeCrashData(_ crashData: [String: Any]) {
        let url = crashLogURL()
        if let jsonData = try? JSONSerialization.data(withJSONObject: crashData, options: .prettyPrinted) {
            try? jsonData.write(to: url, options: .atomic)
        }
    }
    
    private func deleteSavedReport() {
        let url = crashLogURL()
        try? FileManager.default.removeItem(at: url)
    }

    private func crashLogURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(crashLogFile)
    }

    // MARK: - Send Saved Reports

    private func sendCrashReportIfExists() {
        let url = crashLogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let jsonData = try? Data(contentsOf: url),
              let crashData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        Task {
            do {
                // Reconstruct the crash attributes from saved data
                var crashAttributes: [String: AnyEncodable] = [
                    "saved_report": AnyEncodable(true),
                    "device": AnyEncodable(Self.deviceModel)
                ]
                
                if let crashClass = crashData["crash.class"] as? String {
                    crashAttributes["crash.class"] = AnyEncodable(crashClass)
                }
                if let stackTrace = crashData["crash.stackTrace"] as? String {
                    crashAttributes["crash.stackTrace"] = AnyEncodable(stackTrace)
                }
                if let signal = crashData["crash.signal"] as? Int32 {
                    crashAttributes["crash.signal"] = AnyEncodable(signal)
                }
                
                let errorMessage = crashData["action.error"] as? String
                let parentActionIdStr = crashData["parentActionId"] as? String
                let parentActionId = parentActionIdStr.flatMap { UUID(uuidString: $0) }
                let sessionId = crashData["sessionId"] as? String ?? BusinessEventsClient.shared.sessionId
                
                try await BusinessEventsClient.shared.sendCrashReport(
                    parentActionId: parentActionId,
                    sessionId: sessionId,
                    error: errorMessage,
                    extraAttributes: crashAttributes
                )

                // Remove the report file after a successful send
                try FileManager.default.removeItem(at: url)
                os_log("✅ Saved crash report sent and removed", log: OSLog.default, type: .info)
                print("✅ Saved crash report sent and removed")
            } catch {
                os_log("❌ Failed to send saved crash report: %@", log: OSLog.default, type: .error, error.localizedDescription)
                print("❌ Failed to send saved crash report: \(error)")
            }
        }
    }
}
