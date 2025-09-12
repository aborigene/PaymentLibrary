//
//  SwiftyBeaverDynatraceLogger.swift
//  PaymentLibrary
//
//  Created by Simoes, Igor on 12/09/25.
//


import SwiftyBeaver

/// A custom SwiftyBeaver destination that sends logs to a Dynatrace endpoint.
final class DynatraceDestination: BaseDestination {

    // The shared instance of your BusinessEventsClient.
    private let client = BusinessEventsClient.shared
    
    // Overrides the send function to get the formatted log string.
    override public func send(_ level: SwiftyBeaver.Level, msg: String) {
        Task {
            // Create the attributes for the business event.
            let attributes: [String: AnyEncodable] = [
                "message": AnyEncodable(msg),
                "level": AnyEncodable(level.description)
            ]
            
            // Use withAction to send the log event.
            try await client.withAction(
                name: "AppLog.SwiftyBeaver",
                attributes: attributes
            ) {
                // The log has been sent successfully.
            }
        }
    }
}
