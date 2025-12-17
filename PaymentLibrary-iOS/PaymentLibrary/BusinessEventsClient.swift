//
//  BusinessEventsClient.swift
//  PaymentLibrary
//
//  Created by Simoes, Igor on 10/09/25.
//


// BusinessEventsClient.swift
// Dynatrace Business Events (bizevents/ingest) client for iOS (Swift)
// - Singleton with beginAction / endAction
// - Sends CloudEvents to /api/v2/bizevents/ingest when an action finishes
// - Supports parent/child cascades via action.id and action.parentId correlation
//
// Requirements:
//  - Create an API token with scope `bizevents.ingest` OR use OAuth Bearer.
//  - Endpoint (classic env): https://{env}.live.dynatrace.com/api/v2/bizevents/ingest
//  - Content-Type (CloudEvents): application/cloudevent+json
//
// Notes:
//  - We include explicit action fields (action.id, action.parentId, duration) for analyzing cascades.
//
//  - If you prefer pure JSON instead of CloudEvents, switch the encoder at the bottom.
//
import Foundation
import Security
import os.log

// MARK: - Public API

public final class BusinessEventsClient {
    public static let shared = BusinessEventsClient()
    
    // Default configuration values
    public static let defaultEventType = "custom.rum.sdk.action"
    public static let defaultEventProvider = "Custom RUM Application"
    
    // Session management
    private var hasSessionStarted = false
    public private(set) var sessionId: String = UUID().uuidString // Exposed for crash reporting
    private var sessionActionId: UUID?
    
    // Task-local storage for thread-safe action tracking
    @TaskLocal static var currentActionId: UUID?

    public enum Auth {
        case apiToken(String)      // "Authorization: Api-Token <token>"
        case bearer(String)        // "Authorization: Bearer <token>"
    }

    public struct Config {
        public var endpoint: URL                   // .../api/v2/bizevents/ingest
        public var auth: Auth
        public var eventProvider: String          // maps to CloudEvents `source` (→ event.provider)
        public var defaultEventType: String       // e.g. "com.somecustomer.user.action"
        public var appVersion: String?            // optional meta
        public var deviceInfo: String?            // optional meta
        public var deviceMetadata: DeviceMetadataCollector.DeviceMetadata? // comprehensive device metadata
        
        public init(endpoint: URL,
                    auth: Auth,
                    eventProvider: String,
                    defaultEventType: String,
                    appVersion: String? = nil,
                    deviceInfo: String? = nil,
                    deviceMetadata: DeviceMetadataCollector.DeviceMetadata? = nil) {
            self.endpoint = endpoint
            self.auth = auth
            self.eventProvider = eventProvider
            self.defaultEventType = defaultEventType
            self.appVersion = appVersion
            self.deviceInfo = deviceInfo
            self.deviceMetadata = deviceMetadata
        }
    }

    public struct BeginOptions {
        public var name: String
        public var attributes: [String: AnyEncodable]
        public var parentActionId: UUID?
        public init(name: String,
                    attributes: [String: AnyEncodable] = [:],
                    parentActionId: UUID? = nil) {
            self.name = name
            self.attributes = attributes
            self.parentActionId = parentActionId
        }
    }

    // Configure before use
    public func configure(_ config: Config) {
        self.config = config
        
        // Log device metadata for debugging
        if let metadata = config.deviceMetadata {
            os_log("Device Metadata Collected:", log: OSLog.default, type: .debug)
            os_log("OS: %@ - Device: %@", log: OSLog.default, type: .debug, metadata.osVersion, metadata.deviceModel)
            os_log("Network: %@ - Carrier: %@", log: OSLog.default, type: .debug, metadata.networkType, metadata.carrierName ?? "unknown")
        }
        
        // Automatically create session_started event on first configuration
        if !hasSessionStarted {
            createSessionStartedEvent()
        }
    }
    
    /// Convenience configuration method with default values
    /// - Parameters:
    ///   - endpoint: Dynatrace bizevents ingest endpoint
    ///   - auth: Authentication method (API token or Bearer token)
    ///   - eventProvider: Event provider identifier (optional, defaults to "Custom RUM Application")
    ///   - appVersion: Application version (optional)
    ///   - deviceInfo: Device information string (optional)
    public func configure(
        endpoint: URL,
        auth: Auth,
        eventProvider: String? = nil,
        appVersion: String? = nil,
        deviceInfo: String? = nil
    ) {
        let config = Config(
            endpoint: endpoint,
            auth: auth,
            eventProvider: eventProvider ?? BusinessEventsClient.defaultEventProvider,
            defaultEventType: BusinessEventsClient.defaultEventType,
            appVersion: appVersion,
            deviceInfo: deviceInfo
        )
        
        configure(config)
    }

    /// Enhanced configuration method that automatically collects device metadata
    /// - Parameters:
    ///   - endpoint: Dynatrace bizevents ingest endpoint
    ///   - auth: Authentication method (API token or Bearer token)
    ///   - eventProvider: Event provider identifier (optional, defaults to "Custom RUM Application")
    ///   - appVersion: Application version (optional)
    public func configureWithDeviceMetadata(
        endpoint: URL,
        auth: Auth,
        eventProvider: String? = nil,
        appVersion: String? = nil
    ) {
        // Collect comprehensive device metadata
        let deviceMetadata = DeviceMetadataCollector.collectMetadata()
        let deviceInfo = DeviceMetadataCollector.formatDeviceInfo(deviceMetadata)
        
        let config = Config(
            endpoint: endpoint,
            auth: auth,
            eventProvider: eventProvider ?? BusinessEventsClient.defaultEventProvider,
            defaultEventType: BusinessEventsClient.defaultEventType,
            appVersion: appVersion,
            deviceInfo: deviceInfo,
            deviceMetadata: deviceMetadata
        )
        
        configure(config)
    }

    // Start an action; returns actionId you will use to end it
    @discardableResult
    public func beginAction(_ opts: BeginOptions) -> UUID {
        guard let cfg = config else {
            assertionFailure("BusinessEventsClient not configured. Call configure(_:) first.")
            return UUID()
        }
        let now = Date()
        
        // Collect fresh device metadata for this action
        var enhancedAttributes = opts.attributes
        if cfg.deviceMetadata != nil {
            // Collect real-time device metadata
            let currentMetadata = DeviceMetadataCollector.collectMetadata()
            let deviceAttributes = DeviceMetadataCollector.toEventAttributes(currentMetadata)
            
            // Add fresh device metadata to action attributes
            deviceAttributes.forEach { (key, value) in
                switch value {
                case let stringValue as String:
                    enhancedAttributes[key] = AnyEncodable(stringValue)
                case let intValue as Int:
                    enhancedAttributes[key] = AnyEncodable(intValue)
                case let doubleValue as Double:
                    enhancedAttributes[key] = AnyEncodable(doubleValue)
                case let floatValue as Float:
                    enhancedAttributes[key] = AnyEncodable(floatValue)
                case let boolValue as Bool:
                    enhancedAttributes[key] = AnyEncodable(boolValue)
                case let uint64Value as UInt64:
                    enhancedAttributes[key] = AnyEncodable(uint64Value)
                default:
                    enhancedAttributes[key] = AnyEncodable(String(describing: value))
                }
            }
            
            
        }
        
        // Determine effective parent ID: explicit > current action > session action
        // Special case: don't use session action as parent for session_started event itself
        let effectiveParentId = opts.parentActionId ?? Self.currentActionId ?? (opts.name == "session_started" ? nil : sessionActionId)
        
        let ctx = ActionContext(
            id: UUID(),
            name: opts.name,
            startedAt: now,
            attributes: enhancedAttributes, // Use enhanced attributes with fresh metadata
            parentActionId: effectiveParentId, // Use the resolved effective parent ID
            eventType: cfg.defaultEventType
        )
        store.insert(ctx)
        
        os_log("Action '%@' started with fresh device metadata (%d attributes)", log: OSLog.default, type: .debug, ctx.name, enhancedAttributes.count)
        return ctx.id
    }

    // Finish and send immediately
    public func endAction(_ actionId: UUID,
                          status: String = "SUCCESS",
                          error: String? = nil,
                          extraAttributes: [String: AnyEncodable] = [:]) async throws {
        guard let cfg = config else { throw ClientError.notConfigured }
        guard let ctx = store.remove(id: actionId) else { throw ClientError.unknownAction }

        let finishedAt = Date()
        let durationMs = Int((finishedAt.timeIntervalSince(ctx.startedAt))*1000)

        // Merge attributes (extra overrides start-level)
        var data: [String: AnyEncodable] = ctx.attributes
        data.merge(extraAttributes) { _, new in new }
        data["action.id"] = AnyEncodable(ctx.id.uuidString)
        if let p = ctx.parentActionId { data["action.parentId"] = AnyEncodable(p.uuidString) }
        data["action.name"] = AnyEncodable(ctx.name)
        data["action.status"] = AnyEncodable(status)
        if let e = error { data["action.error"] = AnyEncodable(e) }
        data["action.durationMs"] = AnyEncodable(durationMs)
        data["action.starttime"] = AnyEncodable(ctx.startedAt.timeIntervalSince1970*1000)
        data["action.endtime"] = AnyEncodable(finishedAt.timeIntervalSince1970*1000)
        data["session.id"] = AnyEncodable(sessionId)  // Add session.id to every action
        if let v = config?.appVersion { data["app.version"] = AnyEncodable(v) }
        if let d = config?.deviceInfo { data["device.info"] = AnyEncodable(d) }

        let event = CloudEvent(
            specversion: "1.0",
            id: UUID().uuidString,
            source: cfg.eventProvider, // becomes event.provider
            type: ctx.eventType,       // becomes event.type
            time: ISO8601DateFormatter.dtTime.string(from: finishedAt),
            traceparent: nil,
            data: data
        )

        try await send(event: event, config: cfg)
        os_log("Executo end action")
    }
    
    // Synchronous version of endAction for crash scenarios where async context is unreliable
    public func endActionSync(_ actionId: UUID,
                              status: String = "SUCCESS",
                              error: String? = nil,
                              extraAttributes: [String: AnyEncodable] = [:]) throws {
        guard let cfg = config else { throw ClientError.notConfigured }
        guard let ctx = store.remove(id: actionId) else { throw ClientError.unknownAction }

        let finishedAt = Date()
        let durationMs = Int((finishedAt.timeIntervalSince(ctx.startedAt))*1000)

        // Merge attributes (extra overrides start-level)
        var data: [String: AnyEncodable] = ctx.attributes
        data.merge(extraAttributes) { _, new in new }
        data["action.id"] = AnyEncodable(ctx.id.uuidString)
        if let p = ctx.parentActionId { data["action.parentId"] = AnyEncodable(p.uuidString) }
        data["action.name"] = AnyEncodable(ctx.name)
        data["action.status"] = AnyEncodable(status)
        if let e = error { data["action.error"] = AnyEncodable(e) }
        data["action.durationMs"] = AnyEncodable(durationMs)
        data["action.starttime"] = AnyEncodable(ctx.startedAt.timeIntervalSince1970*1000)
        data["action.endtime"] = AnyEncodable(finishedAt.timeIntervalSince1970*1000)
        data["session.id"] = AnyEncodable(sessionId)
        if let v = config?.appVersion { data["app.version"] = AnyEncodable(v) }
        if let d = config?.deviceInfo { data["device.info"] = AnyEncodable(d) }

        let event = CloudEvent(
            specversion: "1.0",
            id: UUID().uuidString,
            source: cfg.eventProvider,
            type: ctx.eventType,
            time: ISO8601DateFormatter.dtTime.string(from: finishedAt),
            traceparent: nil,
            data: data
        )

        try sendSync(event: event, config: cfg)
        os_log("Action ended synchronously with status: %@", log: OSLog.default, type: .info, status)
    }
    

    // Convenience wrapper that auto-finalizes with thread-safe automatic parent-child relationship tracking
    public func withAction<T>(name: String,
                              attributes: [String: AnyEncodable] = [:],
                              parentActionId: UUID? = nil,
                              body: () async throws -> T) async throws -> T {
        // Automatically use current action as parent if no explicit parent provided
        let effectiveParentId = parentActionId ?? Self.currentActionId
        
        let id = beginAction(.init(name: name, attributes: attributes, parentActionId: effectiveParentId))
        
        // Use TaskLocal to maintain thread-safe action context
        return try await Self.$currentActionId.withValue(id) {
            do {
                let result = try await body()
                try await endAction(id, status: "SUCCESS")
                os_log("Action name: \(name)")
                return result
            } catch {
                try? await endAction(id, status: "FAILURE", error: String(describing: error))
                throw error
            }
        }
    }

    // MARK: - Crash Reporting
    
    /// Returns the current action context if available (for crash reporting).
    public func getCurrentActionContext() -> ActionContext? {
        return store.getLastActionContext()
    }
    
    /// Sends a crash report as a business event to Dynatrace (async version).
    /// - Parameters:
    ///   - parentActionId: Optional parent action UUID
    ///   - sessionId: Session ID string
    ///   - error: Error message or description
    ///   - extraAttributes: Additional attributes to include in the event
    public func sendCrashReport(
        parentActionId: UUID?,
        sessionId: String?,
        error: String?,
        extraAttributes: [String: AnyEncodable] = [:]
    ) async throws {
        guard let cfg = config else { throw ClientError.notConfigured }
        
        let now = Date()
        var data: [String: AnyEncodable] = [:]
        
        data["action.id"] = AnyEncodable(UUID().uuidString)
        data["action.starttime"] = AnyEncodable(now.timeIntervalSince1970*1000)
        if let parentId = parentActionId {
            data["action.parentId"] = AnyEncodable(parentId.uuidString)
        }
        if let session = sessionId {
            data["session.id"] = AnyEncodable(session)
        }
        if let errorMsg = error {
            data["action.error"] = AnyEncodable(errorMsg)
        }
        
        // Merge extra attributes
        data.merge(extraAttributes) { _, new in new }
        
        // Add app version and device info if available
        if let v = cfg.appVersion {
            data["app.version"] = AnyEncodable(v)
        }
        if let d = cfg.deviceInfo {
            data["device.info"] = AnyEncodable(d)
        }
        
        // Add device metadata attributes if available
        if let metadata = cfg.deviceMetadata {
            let deviceAttributes = DeviceMetadataCollector.toEventAttributes(metadata)
            for (key, value) in deviceAttributes {
                // Convert Any to AnyEncodable based on runtime type
                if let stringValue = value as? String {
                    data[key] = AnyEncodable(stringValue)
                } else if let intValue = value as? Int {
                    data[key] = AnyEncodable(intValue)
                } else if let doubleValue = value as? Double {
                    data[key] = AnyEncodable(doubleValue)
                } else if let boolValue = value as? Bool {
                    data[key] = AnyEncodable(boolValue)
                } else {
                    data[key] = AnyEncodable(String(describing: value))
                }
            }
        }
        
        let eventType = "custom.rum.sdk.crash"
        let eventProvider = cfg.eventProvider.isEmpty ? "Custom RUM Application" : cfg.eventProvider
        
        let event = CloudEvent(
            specversion: "1.0",
            id: UUID().uuidString,
            source: eventProvider,
            type: eventType,
            time: ISO8601DateFormatter.dtTime.string(from: now),
            traceparent: nil,
            data: data
        )
        
        try await send(event: event, config: cfg)
    }
    
    /// Sends a crash report synchronously - USE THIS for crash handlers where async context is unreliable.
    /// This method blocks the calling thread until the network request completes or times out.
    /// - Parameters:
    ///   - parentActionId: Optional parent action UUID
    ///   - sessionId: Session ID string
    ///   - error: Error message or description
    ///   - extraAttributes: Additional attributes to include in the event
    public func sendCrashReportSync(
        parentActionId: UUID?,
        sessionId: String?,
        error: String?,
        extraAttributes: [String: AnyEncodable] = [:]
    ) throws {
        guard let cfg = config else { throw ClientError.notConfigured }
        
        let now = Date()
        var data: [String: AnyEncodable] = [:]
        
        data["action.id"] = AnyEncodable(UUID().uuidString)
        data["action.name"] = AnyEncodable("crash")
        data["action.status"] = AnyEncodable("FAILURE")
        data["action.starttime"] = AnyEncodable(now.timeIntervalSince1970*1000)
        
        if let parentId = parentActionId {
            data["action.parentId"] = AnyEncodable(parentId.uuidString)
        }
        if let session = sessionId {
            data["session.id"] = AnyEncodable(session)
        }
        if let errorMsg = error {
            data["action.error"] = AnyEncodable(errorMsg)
        }
        
        // Merge extra attributes
        data.merge(extraAttributes) { _, new in new }
        
        // Add app version and device info if available
        if let v = cfg.appVersion {
            data["app.version"] = AnyEncodable(v)
        }
        if let d = cfg.deviceInfo {
            data["device.info"] = AnyEncodable(d)
        }
        
        // Add device metadata attributes if available
        if let metadata = cfg.deviceMetadata {
            let deviceAttributes = DeviceMetadataCollector.toEventAttributes(metadata)
            for (key, value) in deviceAttributes {
                // Convert Any to AnyEncodable based on runtime type
                if let stringValue = value as? String {
                    data[key] = AnyEncodable(stringValue)
                } else if let intValue = value as? Int {
                    data[key] = AnyEncodable(intValue)
                } else if let doubleValue = value as? Double {
                    data[key] = AnyEncodable(doubleValue)
                } else if let boolValue = value as? Bool {
                    data[key] = AnyEncodable(boolValue)
                } else {
                    data[key] = AnyEncodable(String(describing: value))
                }
            }
        }
        
        let eventType = "custom.rum.sdk.crash"
        let eventProvider = cfg.eventProvider.isEmpty ? "Custom RUM Application" : cfg.eventProvider
        
        let event = CloudEvent(
            specversion: "1.0",
            id: UUID().uuidString,
            source: eventProvider,
            type: eventType,
            time: ISO8601DateFormatter.dtTime.string(from: now),
            traceparent: nil,
            data: data
        )
        
        // Log the complete event before sending
        if let eventJSON = try? JSONEncoder.dynatrace.encode(event),
           let eventString = String(data: eventJSON, encoding: .utf8) {
            os_log("🔵 COMPLETE CRASH EVENT: %@", log: OSLog.default, type: .info, eventString)
            print("🔵 COMPLETE CRASH EVENT:\n\(eventString)")
        }
        
        try sendSync(event: event, config: cfg)
        os_log("Crash report sent synchronously", log: OSLog.default, type: .info)
    }

    // MARK: - Internals

    public enum ClientError: Error { case notConfigured, unknownAction, badResponse(Int) }

    public struct ActionContext {
        public let id: UUID
        public let name: String
        public let startedAt: Date
        public let attributes: [String: AnyEncodable]
        public let parentActionId: UUID?
        public let eventType: String
    }

    private var config: Config?
    private let store = InMemoryStore()

    private func send(event: CloudEvent, config: Config) async throws {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        switch config.auth {
        case .apiToken(let token):
            request.setValue("Api-Token \(token)", forHTTPHeaderField: "Authorization")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/cloudevent+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.dynatrace.encode(event)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        // 202 means accepted; 400 can be partial success per API docs, but here we treat as error to re-evaluate payload
        guard code == 202 else {
            // Try to surface server-provided error content for easier debugging
            let _ = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.badResponse(code)
        }
    }
    
    /// Synchronous send method specifically for crash reporting where async context is unreliable
    private func sendSync(event: CloudEvent, config: Config) throws {
        os_log("🔵 sendSync: Starting synchronous network request to %@", log: OSLog.default, type: .info, config.endpoint.absoluteString)
        print("🔵 sendSync: Endpoint = \(config.endpoint)")
        
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0 // Increase timeout for crash scenarios
        
        switch config.auth {
        case .apiToken(let token):
            request.setValue("Api-Token \(token)", forHTTPHeaderField: "Authorization")
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/cloudevent+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.dynatrace.encode(event)

        print("🔵 sendSync: Request configured, creating URLSession task...")
        
        // Use semaphore to make synchronous request
        let semaphore = DispatchSemaphore(value: 0)
        var responseCode: Int = -1
        var responseError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            print("🔵 sendSync: Network callback received")
            if let error = error {
                print("🔵 sendSync: Error = \(error)")
                responseError = error
            } else {
                responseCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("🔵 sendSync: Response code = \(responseCode)")
            }
            semaphore.signal()
        }
        
        print("🔵 sendSync: Starting task...")
        task.resume()
        
        print("🔵 sendSync: Waiting for response (timeout: 10s)...")
        // Wait for completion with timeout
        let timeout = semaphore.wait(timeout: .now() + 10.0)
        
        if timeout == .timedOut {
            print("❌ sendSync: Request TIMED OUT")
            os_log("❌ sendSync: Request timed out", log: OSLog.default, type: .error)
            task.cancel()
            throw ClientError.badResponse(-1)
        }
        
        if let error = responseError {
            print("❌ sendSync: Network error = \(error)")
            throw error
        }
        
        guard responseCode == 202 else {
            print("❌ sendSync: Bad response code = \(responseCode)")
            os_log("❌ sendSync: Bad response code %d", log: OSLog.default, type: .error, responseCode)
            throw ClientError.badResponse(responseCode)
        }
        
        print("✅ sendSync: Successfully sent (202 Accepted)")
        os_log("✅ sendSync: Successfully sent crash report", log: OSLog.default, type: .info)
    }

    
    // MARK: - Session Management
    
    /// Creates a session_started business event with comprehensive device metadata
    /// This is called automatically when BusinessEventsClient is first configured
    private func createSessionStartedEvent() {
        guard let cfg = config else {
            os_log("Cannot create session_started event: BusinessEventsClient not configured", log: OSLog.default, type: .error)
            return
        }
        
        // Mark session as started to prevent duplicate events
        hasSessionStarted = true
        
        Task {
            do {
                // Collect fresh device metadata for session start
                let currentMetadata = DeviceMetadataCollector.collectMetadata()
                let deviceAttributes = DeviceMetadataCollector.toEventAttributes(currentMetadata)
                
                // Convert to AnyEncodable dictionary
                var attributes: [String: AnyEncodable] = [:]
                deviceAttributes.forEach { (key, value) in
                    switch value {
                    case let stringValue as String:
                        attributes[key] = AnyEncodable(stringValue)
                    case let intValue as Int:
                        attributes[key] = AnyEncodable(intValue)
                    case let doubleValue as Double:
                        attributes[key] = AnyEncodable(doubleValue)
                    case let floatValue as Float:
                        attributes[key] = AnyEncodable(floatValue)
                    case let boolValue as Bool:
                        attributes[key] = AnyEncodable(boolValue)
                    case let uint64Value as UInt64:
                        attributes[key] = AnyEncodable(uint64Value)
                    default:
                        attributes[key] = AnyEncodable(String(describing: value))
                    }
                }
                
                // Add session-specific attributes
                attributes["session.id"] = AnyEncodable(sessionId)
                attributes["session.start_time"] = AnyEncodable(ISO8601DateFormatter().string(from: Date()))
                attributes["event.provider"] = AnyEncodable(cfg.eventProvider)
                attributes["session.initialization_type"] = AnyEncodable("business_events_configured")
                
                // Begin session_started event - this will become the parent for all first-level actions
                let actionId = beginAction(BeginOptions(
                    name: "session_started",
                    attributes: attributes
                ))
                
                // Store session action ID to use as default parent for first-level actions
                sessionActionId = actionId
                
                // End session_started event immediately
                try await endAction(
                    actionId,
                    status: "SUCCESS",
                    extraAttributes: [
                        "session.duration_ms": AnyEncodable(0),
                        "session.components_initialized": AnyEncodable([
                            "BusinessEventsClient",
                            "DeviceMetadataCollector"
                        ])
                    ]
                )
                
                os_log("Session started event created successfully", log: OSLog.default, type: .info)
                
            } catch {
                os_log("Failed to create session_started event: %@", log: OSLog.default, type: .error, error.localizedDescription)
            }
        }
    }
}

// MARK: - CloudEvents payload

private struct CloudEvent: Encodable {
    let specversion: String          // "1.0"
    let id: String                   // event id
    let source: String               // → event.provider
    let type: String                 // → event.type
    let time: String?                // RFC3339/ISO8601
    let traceparent: String?         // Not used - correlation via action.id instead
    let data: [String: AnyEncodable] // business payload
}

// MARK: - In-memory store (thread-safe)

private final class InMemoryStore {
    private var dict: [UUID: BusinessEventsClient.ActionContext] = [:]
    private let q = DispatchQueue(label: "biz.store")
    public func insert(_ ctx: BusinessEventsClient.ActionContext) { q.sync { dict[ctx.id] = ctx } }
    public func lookup(id: UUID) -> BusinessEventsClient.ActionContext? { q.sync { dict[id] } }
    public func remove(id: UUID) -> BusinessEventsClient.ActionContext? { q.sync { dict.removeValue(forKey: id) } }
    public func getLastActionContext() -> BusinessEventsClient.ActionContext? {
        q.sync { dict.values.sorted { $0.startedAt > $1.startedAt }.first }
    }
}

// MARK: - AnyEncodable helper

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) { self._encode = wrapped.encode }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - JSON Encoder tuned for Dynatrace

private extension JSONEncoder {
    static let dynatrace: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = []
        return enc
    }()
}

// MARK: - ISO8601 formatter with fractional seconds

private extension ISO8601DateFormatter {
    static let dtTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Example usage
/*
 Usage example:

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let endpoint = URL(string: "https://YOUR_ENV.live.dynatrace.com/api/v2/bizevents/ingest")!
        BusinessEventsClient.shared.configure(.init(
            endpoint: endpoint,
            auth: .apiToken("dt0c01.abc123......"),
            eventProvider: "com.unitedgames.payment.ios",
            defaultEventType: "com.unitedgames.user.action",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            deviceInfo: UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        ))
        return true
    }
}

// Somewhere in the app
let parent = BusinessEventsClient.shared.beginAction(.init(name: "Checkout"))
let child = BusinessEventsClient.shared.beginAction(.init(name: "AddCard", parentActionId: parent))
Task {
    try await BusinessEventsClient.shared.endAction(child, status: "SUCCESS")
    try await BusinessEventsClient.shared.endAction(parent, status: "SUCCESS")
}
*/

