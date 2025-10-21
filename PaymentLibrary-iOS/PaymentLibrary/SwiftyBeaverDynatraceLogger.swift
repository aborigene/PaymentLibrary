    
import Foundation

// MARK: - Dynatrace Log Event Structure

/// Helper structure to represent a single log line ready for JSON encoding to the Dynatrace API.
struct DynatraceLogEvent: Encodable {
    let timestamp: Int64
    let level: String
    let message: String
    
    // Dynatrace-specific fields for enrichment
    let dtSource: String
    let logSource: String
    
    // Contextual log data provided by SwiftyBeaver
    let thread: String
    let file: String
    let function: String
    let line: Int

    // Custom CodingKeys to map Swift properties to Dynatrace's required JSON field names
    enum CodingKeys: String, CodingKey {
        case timestamp, level, message, thread, file, function, line
        case dtSource = "dt.source"
        case logSource = "log.source"
    }
}

// MARK: - SwiftyBeaver.Level Extension
private extension SwiftyBeaver.Level {
    /// Returns the uppercase string representation of the log level name.
    var stringName: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        // Cases based on the user-provided enum definition
        case .critical: return "CRITICAL"
        case .fault: return "FAULT"
        }
    }
}

// MARK: - Dynatrace Destination

/// A custom SwiftyBeaver destination that sends logs as JSON payload to the Dynatrace Log Ingest API.
final class DynatraceDestination: BaseDestination {

    // Configuration for the Dynatrace API
    private let dtEndpoint: String
    private let dtApiToken: String
    private let applicationName: String
    
    // Configuration for the Retry Mechanism (Exponential Backoff)
    private let maxRetryAttempts = 3
    private let initialRetryDelaySeconds: Double = 2.0 // Initial delay: 2s (will double on subsequent retries)
    
    // MARK: Initialization

    /**
     Initializes the Dynatrace destination with necessary configuration.

     - Parameters:
        - endpoint: The Dynatrace Log Ingest API endpoint URL (e.g., "https://<YOUR_TENANT>.live.dynatrace.com/api/v2/logs/ingest").
        - apiToken: The Dynatrace API token with `logs.ingest` permission.
        - appName: The name to identify this application in Dynatrace (used for `dt.source`).
    */
    init(endpoint: String, apiToken: String, appName: String) {
        self.dtEndpoint = endpoint
        self.dtApiToken = apiToken
        self.applicationName = appName
        super.init()
    }
    
    // MARK: Overridden Send Method

    /// Overrides the required synchronous `send` function to capture all log details.
//    override public func send(
//        _ level: SwiftyBeaver.Level,
//        msg: String,
//        thread: String,
//        file: String,
//        function: String,
//        line: UInt,
//        context: Any?
//    ) -> String? {
                        //send(_ level: SwiftyBeaver.Level, msg: String, thread: String, file: String, function: String, line: Int, context: Any? = nil) -> String?
    override public func send(_ level: SwiftyBeaver.Level,
                              msg: String,
                              thread: String,
                              file: String,
                              function: String,
                              line: Int, context: Any? = nil) -> String? {
        // 1. Create the log event payload
        let logEvent = DynatraceLogEvent(
            timestamp: Int64(Date().timeIntervalSince1970 * 1000), // Current time in milliseconds
            level: level.stringName, // Ensure level is uppercase string (e.g., "INFO")
            message: msg,
            dtSource: self.applicationName,
            logSource: "SwiftyBeaver",
            thread: thread,
            file: file,
            function: function,
            line: line
        )
        
        // 2. Execute the asynchronous HTTP call in a detached task
        Task {
            do {
                // The Dynatrace Log API expects an array of log lines
                try await self.sendLogToDynatrace(events: [logEvent])
            } catch {
                // Log the final failure internally after all retries have been exhausted
                print("Failed to send log to Dynatrace after \(maxRetryAttempts) attempts: \(error)")
            }
        }
        
        // Return nil to indicate that this destination does not modify the log string for other destinations
        return nil
    }

    // MARK: Asynchronous HTTP Call with Retry Logic

    /// Performs the HTTP POST request to the Dynatrace Log Ingest API with exponential backoff retries.
    private func sendLogToDynatrace(events: [DynatraceLogEvent]) async throws {
        guard let url = URL(string: dtEndpoint) else {
            throw DynatraceError.invalidURLEndpoint
        }

        // --- Prepare static request properties (same for all retries) ---
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Api-Token \(dtApiToken)", forHTTPHeaderField: "Authorization")
        
        // Serialize the log event array to JSON Data
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(events)

        // --- Retry Loop ---
        for attempt in 0..<maxRetryAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DynatraceError.invalidResponse
                }

                if httpResponse.statusCode == 204 {
                    return // Success!
                }
                
                let responseString = String(data: data, encoding: .utf8) ?? "No error message provided"
                
                // Determine if the server response is retriable (5xx or 429) or permanent (other 4xx)
                let error: DynatraceError
                if httpResponse.statusCode >= 500 || httpResponse.statusCode == 429 {
                    // 5xx (Server Error) and 429 (Too Many Requests) are temporary and retriable
                    error = .serverError(statusCode: httpResponse.statusCode, body: responseString)
                } else {
                    // Other 4xx errors (400, 401, 403, etc.) are permanent and non-retriable
                    error = .nonRetriableError(statusCode: httpResponse.statusCode, body: responseString)
                }
                
                if !error.isRetriable || attempt == maxRetryAttempts - 1 {
                    // Final failure or a permanent (4xx excluding 429) error, throw immediately/after last attempt
                    print("Dynatrace send failed permanently (Status \(httpResponse.statusCode)): \(responseString)")
                    throw error
                }
                
                // Retriable error (5xx or 429), pause and retry
                let delay = initialRetryDelaySeconds * pow(2.0, Double(attempt))
                let duration = UInt64(delay * 1_000_000_000)
                print("Dynatrace send failed (Attempt \(attempt + 1) of \(maxRetryAttempts), Status \(httpResponse.statusCode)). Retrying in \(String(format: "%.1f", delay)) seconds...")
                try await Task.sleep(nanoseconds: duration)

            } catch {
                // Catch network-level errors (like timeouts, no connectivity)
                
                if attempt == maxRetryAttempts - 1 {
                    print("Dynatrace send failed permanently (Network error) after \(maxRetryAttempts) attempts: \(error)")
                    throw DynatraceError.networkError(error)
                }
                
                // Pause and retry for network errors
                let delay = initialRetryDelaySeconds * pow(2.0, Double(attempt))
                let duration = UInt64(delay * 1_000_000_000)
                print("Dynatrace send failed (Attempt \(attempt + 1) of \(maxRetryAttempts), Network Error: \(error.localizedDescription)). Retrying in \(String(format: "%.1f", delay)) seconds...")
                try await Task.sleep(nanoseconds: duration)
            }
        }
        // This line should technically be unreachable, but is included for completeness
        throw DynatraceError.serverError(statusCode: 0, body: "Exited retry loop unexpectedly.")
    }
}

// MARK: - Custom Error Types

enum DynatraceError: Error {
    case invalidURLEndpoint
    case invalidResponse
    case serverError(statusCode: Int, body: String)
    case nonRetriableError(statusCode: Int, body: String)
    case networkError(Error)
    
    /// Determines if the error is temporary (e.g., 5xx server error, 429 rate limit, network timeout) and should be retried.
    var isRetriable: Bool {
        switch self {
        case .serverError, .networkError, .invalidResponse:
            // 5xx errors, 429 (handled upstream in sendLogToDynatrace), network failure, or bad/non-HTTP response are retriable
            return true
        case .invalidURLEndpoint, .nonRetriableError:
            // Invalid URL or non-retriable 4xx errors are not retriable
            return false
        }
    }
}
