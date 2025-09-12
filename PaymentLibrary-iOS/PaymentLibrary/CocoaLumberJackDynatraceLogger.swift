//
//  CocoaLumberjackDynatraceLogger.swift
//  PaymentLibrary
//
//  Created by Simoes, Igor on 12/09/25.
//


import CocoaLumberjack


/// A custom CocoaLumberjack logger that sends logs to a Dynatrace endpoint.
final class DynatraceLogger: DDAbstractLogger {
    
    // Uses the shared instance of your BusinessEventsClient.
    private let client = BusinessEventsClient.shared
    
    override public var logFormatter: DDLogFormatter? {
        didSet {
            // Optional: you can set a custom formatter here
        }
    }
    
    override func log(message logMessage: DDLogMessage) {
        Task {
            // Converts the DDLogMessage to a dictionary for the business event payload.
            let attributes: [String: AnyEncodable] = [
                "message": AnyEncodable(logMessage.message),
                //"level": ,AnyEncodable("XXXX"),
                "threadID": AnyEncodable(logMessage.threadID),
                "function": AnyEncodable(logMessage.function),
                "file": AnyEncodable(logMessage.file),
                "line": AnyEncodable(logMessage.line)
            ]
            
            // Use withAction to send the log event.
            try await client.withAction(
                name: "AppLog.Lumberjack",
                attributes: attributes
            ) {
                // The log has been sent successfully.
            }
        }
    }
}
