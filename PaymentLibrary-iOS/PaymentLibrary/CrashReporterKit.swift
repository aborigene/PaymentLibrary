//
//  CrashReporterKit.swift
//  PaymentLibrary
//
//  Created by Simoes, Igor on 12/09/25.
//


//
//  CrashReporterKit.swift
//

import Foundation
import UIKit
import os.log

final class CrashReporterKit {
    static let shared = CrashReporterKit()
    private let crashLogFile = "crash_log.txt"

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
        let report = """
        [EXCEPTION]
        Name: \(exception.name)
        Reason: \(exception.reason ?? "unknown")
        Stack Trace:
        \(exception.callStackSymbols.joined(separator: "\n"))
        """
        writeReport(report)
        sendCrashReportIfExists()
    }

    // MARK: - Signal Handling

    private func setupSignalHandler() {
        typealias SignalHandler = @convention(c) (Int32) -> Void
        let handler: SignalHandler = { signal in
            let report = "[SIGNAL] App crashed with signal: \(signal)"
            CrashReporterKit.shared.writeReport(report)
            exit(signal)
        }

        signal(SIGABRT, handler)
        signal(SIGILL, handler)
        signal(SIGSEGV, handler)
        signal(SIGFPE, handler)
        signal(SIGBUS, handler)
        signal(SIGPIPE, handler)
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

    // MARK: - Send to API

    private func sendCrashReportIfExists() {
           let url = crashLogURL()
           guard FileManager.default.fileExists(atPath: url.path),
                 let content = try? String(contentsOf: url) else { return }

           // Use the PaymentClient's BusinessEventsClient to send the report
           Task {
               do {
                   let crashAttributes: [String: AnyEncodable] = [
                       "crash.details": AnyEncodable(content)
                   ]
                   
                   // Use the withAction wrapper to automatically end the event
                   try await BusinessEventsClient.shared.withAction(
                       name: "CrashReport.send",
                       attributes: crashAttributes
                   ) {
                       os_log("Crash report sent as a business event.", type: .info)
                   }

                   // Remove the report file after a successful send
                   try FileManager.default.removeItem(at: url)
               } catch {
                   os_log("Failed to send crash report via BusinessEventsClient: %@", type: .error, error.localizedDescription)
               }
           }
       }

    private func sendReportToAPI(_ report: String) {
        guard let apiURL = URL(string: "https://your-api.com/crash-report") else { return }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["crash_report": report]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request).resume()
    }
}
