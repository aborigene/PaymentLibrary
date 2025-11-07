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
        sendCrashReportIfExists()
    }

    // MARK: - Exception Handling

    private func handle(exception: NSException) {
        let stackTrace = exception.callStackSymbols.joined(separator: "\n")
        let errorMessage = exception.reason ?? "unknown"
        
        let extraAttributes: [String: AnyEncodable] = [
            "crash.class": AnyEncodable(exception.name.rawValue),
            "crash.stackTrace": AnyEncodable(stackTrace),
            "device": AnyEncodable(Self.deviceModel)
        ]
        
        // Get current action context for parentActionId and sessionId
        let actionContext = BusinessEventsClient.shared.getCurrentActionContext()
        let parentActionId = actionContext?.parentActionId
        let sessionId = BusinessEventsClient.shared.sessionId
        
        // Send crash report synchronously using a semaphore to block until complete
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                try await BusinessEventsClient.shared.sendCrashReport(
                    parentActionId: parentActionId,
                    sessionId: sessionId,
                    error: errorMessage,
                    extraAttributes: extraAttributes
                )
                os_log("Crash report sent successfully", log: OSLog.default, type: .info)
            } catch {
                os_log("Failed to send crash report: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
            semaphore.signal()
        }
        
        // Block until the crash report is sent (with timeout)
        _ = semaphore.wait(timeout: .now() + 5.0)
        
        // Write to file for backup
        let report = """
        [EXCEPTION]
        Name: \(exception.name)
        Reason: \(errorMessage)
        Stack Trace:
        \(stackTrace)
        """
        writeReport(report)
    }

    // MARK: - Signal Handling

    private func setupSignalHandler() {
        func handleSignal(_ signal: Int32) {
            let errorMessage = "App crashed with signal: \(signal)"
            
            let extraAttributes: [String: AnyEncodable] = [
                "crash.class": AnyEncodable("Signal"),
                "crash.signal": AnyEncodable(signal),
                "device": AnyEncodable(CrashReporterKit.deviceModel)
            ]
            
            // Get current action context for parentActionId and sessionId
            let actionContext = BusinessEventsClient.shared.getCurrentActionContext()
            let parentActionId = actionContext?.parentActionId
            let sessionId = BusinessEventsClient.shared.sessionId
            
            // Send crash report synchronously
            let semaphore = DispatchSemaphore(value: 0)
            
            Task {
                do {
                    try await BusinessEventsClient.shared.sendCrashReport(
                        parentActionId: parentActionId,
                        sessionId: sessionId,
                        error: errorMessage,
                        extraAttributes: extraAttributes
                    )
                    os_log("Signal crash report sent successfully", log: OSLog.default, type: .info)
                } catch {
                    os_log("Failed to send signal crash report: %@", log: OSLog.default, type: .error, error.localizedDescription)
                }
                semaphore.signal()
            }
            
            // Block until the crash report is sent (with timeout)
            _ = semaphore.wait(timeout: .now() + 5.0)
            
            let report = "[SIGNAL] \(errorMessage)"
            CrashReporterKit.shared.writeReport(report)
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
        let parentActionId = actionContext?.parentActionId
        let sessionId = BusinessEventsClient.shared.sessionId
        
        // Send crash report synchronously
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                try await BusinessEventsClient.shared.sendCrashReport(
                    parentActionId: parentActionId,
                    sessionId: sessionId,
                    error: errorMessage,
                    extraAttributes: extraAttributes
                )
                os_log("Manual crash report sent successfully", log: OSLog.default, type: .info)
            } catch {
                os_log("Failed to send manual crash report: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
            semaphore.signal()
        }
        
        // Block until the crash report is sent (with timeout)
        _ = semaphore.wait(timeout: .now() + 5.0)
    }

    // MARK: - Save Report

    private func writeReport(_ report: String) {
        let url = crashLogURL()
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func crashLogURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(crashLogFile)
    }

    // MARK: - Send Saved Reports

    private func sendCrashReportIfExists() {
        let url = crashLogURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        Task {
            do {
                let crashAttributes: [String: AnyEncodable] = [
                    "crash.details": AnyEncodable(content),
                    "crash.type": AnyEncodable("saved_report")
                ]
                
                let sessionId = BusinessEventsClient.shared.sessionId
                
                try await BusinessEventsClient.shared.sendCrashReport(
                    parentActionId: nil,
                    sessionId: sessionId,
                    error: "Saved crash report",
                    extraAttributes: crashAttributes
                )

                // Remove the report file after a successful send
                try FileManager.default.removeItem(at: url)
                os_log("Saved crash report sent and removed", log: OSLog.default, type: .info)
            } catch {
                os_log("Failed to send saved crash report: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
        }
    }
}
