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
    public static let defaultEventProvider = "CustomRumSDK"
    
    // Session management
    private var hasSessionStarted = false
    public private(set) var sessionId: String = UUID().uuidString // Exposed for crash reporting
    private var sessionActionId: UUID?
    
    // Task-local storage for thread-safe action tracking
    @TaskLocal static var currentActionId: UUID?

    public enum LogLevel: Int, Comparable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warn = 3
        case error = 4
        case none = 5
        
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    // Log level configuration - defaults to DEBUG
    private var logLevel: LogLevel = .debug

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
        public var actionTimeoutSeconds: TimeInterval // timeout in seconds before auto-finishing actions
        public var logLevel: LogLevel              // default log level (default: .info)
        
        public init(endpoint: URL,
                    auth: Auth,
                    eventProvider: String,
                    defaultEventType: String,
                    appVersion: String? = nil,
                    deviceInfo: String? = nil,
                    deviceMetadata: DeviceMetadataCollector.DeviceMetadata? = nil,
                    actionTimeoutSeconds: TimeInterval = 7.0,
                    logLevel: LogLevel = .debug) {
            self.endpoint = endpoint
            self.auth = auth
            self.eventProvider = eventProvider
            self.defaultEventType = defaultEventType
            self.appVersion = appVersion
            self.deviceInfo = deviceInfo
            self.deviceMetadata = deviceMetadata
            self.actionTimeoutSeconds = actionTimeoutSeconds
            self.logLevel = logLevel
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

    // Helper methods for logging with level check
    private func logV(_ message: String, _ args: CVarArg...) {
        guard logLevel <= .verbose else { return }
        os_log("%@", log: .default, type: .debug, String(format: message, arguments: args))
    }
    
    private func logD(_ message: String, _ args: CVarArg...) {
        guard logLevel <= .debug else { return }
        os_log("%@", log: .default, type: .debug, String(format: message, arguments: args))
    }
    
    private func logI(_ message: String, _ args: CVarArg...) {
        guard logLevel <= .info else { return }
        os_log("%@", log: .default, type: .info, String(format: message, arguments: args))
    }
    
    private func logW(_ message: String, _ args: CVarArg...) {
        guard logLevel <= .warn else { return }
        os_log("%@", log: .default, type: .default, String(format: message, arguments: args))
    }
    
    private func logE(_ message: String, _ args: CVarArg...) {
        guard logLevel <= .error else { return }
        os_log("%@", log: .default, type: .error, String(format: message, arguments: args))
    }

    // Configure before use
    public func configure(_ config: Config) {
        self.config = config
        self.logLevel = config.logLevel
        
        // Log device metadata for debugging
        if let metadata = config.deviceMetadata {
            logD("Device Metadata Collected:")
            logD("OS: %@ - Device: %@", metadata.osVersion, metadata.deviceModel)
            logD("Network: %@ - Carrier: %@", metadata.networkType, metadata.carrierName ?? "unknown")
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
    ///   - eventProvider: Event provider identifier (optional, defaults to "CustomRumSDK")
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
    ///   - eventProvider: Event provider identifier (optional, defaults to "CustomRumSDK")
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
        
        var ctx = ActionContext(
            id: UUID(),
            name: opts.name,
            startedAt: now,
            attributes: enhancedAttributes, // Use enhanced attributes with fresh metadata
            parentActionId: effectiveParentId, // Use the resolved effective parent ID
            eventType: cfg.defaultEventType,
            timeoutTimer: nil
        )
        
        // Schedule timeout timer
        let timer = Timer.scheduledTimer(withTimeInterval: cfg.actionTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task {
                do {
                    try await self.endAction(ctx.id, status: "TIMEOUT", error: "Action exceeded timeout of \(cfg.actionTimeoutSeconds)s")
                    self.logI("Action '%@' auto-finished with TIMEOUT status", ctx.name)
                } catch ClientError.unknownAction {
                    // Action was already finished by user code - this is expected and not an error
                    self.logD("Action '%@' was already finished when timeout fired", ctx.name)
                } catch {
                    self.logE("Failed to auto-finish timed out action '%@': %@", ctx.name, error.localizedDescription)
                }
            }
        }
        ctx.timeoutTimer = timer
        
        store.insert(ctx)
        
        logD("Action '%@' started with fresh device metadata (%d attributes), timeout: %.1fs", ctx.name, enhancedAttributes.count, cfg.actionTimeoutSeconds)
        return ctx.id
    }

    // Finish and send immediately
    public func endAction(_ actionId: UUID,
                          status: String = "SUCCESS",
                          error: String? = nil,
                          extraAttributes: [String: AnyEncodable] = [:]) async throws {
        guard let cfg = config else { throw ClientError.notConfigured }
        guard var ctx = store.remove(id: actionId) else { throw ClientError.unknownAction }
        
        // Cancel timeout timer since action is ending normally
        ctx.timeoutTimer?.invalidate()
        ctx.timeoutTimer = nil

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
        logD("Executo end action")
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
                do {
                    try await endAction(id, status: "SUCCESS")
                    logD("Action name: %@", name)
                } catch ClientError.unknownAction {
                    // Action was already finished by timeout - this is expected
                    logD("Action '%@' was already finished (likely by timeout)", name)
                }
                return result
            } catch {
                do {
                    try await endAction(id, status: "FAILURE", error: String(describing: error))
                } catch ClientError.unknownAction {
                    // Action was already finished by timeout - this is expected
                    logD("Action '%@' was already finished when trying to record failure (likely by timeout)", name)
                } catch {
                    // Log other endAction errors but don't fail
                    logE("Failed to send error event: %@", error.localizedDescription)
                }
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
        data["action.name"] = AnyEncodable("crash")
        data["action.status"] = AnyEncodable("CRASH")
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
        
        // Add mapping file identifiers for deobfuscation
        let frameworkBundle = Bundle(for: BusinessEventsClient.self)
        if let bundleId = frameworkBundle.bundleIdentifier {
            data["crash.bundleId"] = AnyEncodable(bundleId)
            os_log("✅ crash.bundleId = %@", log: .default, type: .info, bundleId)
        } else {
            os_log("⚠️ crash.bundleId is nil", log: .default, type: .default)
        }
        if let version = frameworkBundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            data["crash.version"] = AnyEncodable(version)
            os_log("✅ crash.version = %@", log: .default, type: .info, version)
        } else {
            os_log("⚠️ crash.version is nil", log: .default, type: .default)
        }
        if let build = frameworkBundle.infoDictionary?["CFBundleVersion"] as? String {
            data["crash.build"] = AnyEncodable(build)
            os_log("✅ crash.build = %@", log: .default, type: .info, build)
        } else {
            os_log("⚠️ [Sync] crash.build not found in bundle info", log: .default, type: .default)
        }
        if let uuid = getBinaryUUID() {
            data["crash.uuid"] = AnyEncodable(uuid)
            os_log("✅ crash.uuid = %@", log: .default, type: .info, uuid)
        } else {
            os_log("❌ crash.uuid is nil - getBinaryUUID() returned nil", log: .default, type: .error)
        }
        
        // Collect loaded images and filter by stack trace
        let allLoadedImages = getLoadedImages()
        logD("getLoadedImages() returned %d total images", allLoadedImages.count)
        
        // Filter images to only those referenced in the stack trace
        // Extract stack trace string from AnyEncodable by encoding/decoding
        var stackTrace = ""
        if let stackTraceEncodable = extraAttributes["crash.stackTrace"] {
            // Try to encode and decode to extract the underlying String
            if let jsonData = try? JSONEncoder().encode(stackTraceEncodable),
               let decodedString = try? JSONDecoder().decode(String.self, from: jsonData) {
                stackTrace = decodedString
                logD("✅ Successfully extracted stack trace from AnyEncodable (%d chars)", decodedString.count)
            } else {
                logW("⚠️ Failed to extract stack trace from AnyEncodable")
            }
        } else {
            logW("⚠️ No crash.stackTrace found in extraAttributes")
        }
        
        let filteredImages = filterImagesByStackTrace(allImages: allLoadedImages, stackTrace: stackTrace)
        
        if !filteredImages.isEmpty {
            data["crash.loaded_images"] = AnyEncodable(filteredImages)
            logI("✅ Added crash.loaded_images with %d entries (filtered from %d)", filteredImages.count, allLoadedImages.count)
            // Log all filtered images
            for (index, image) in filteredImages.enumerated() {
                logD("  Image[%d]: %@ at %@", index, image["name"] ?? "unknown", image["base_address"] ?? "unknown")
            }
        } else {
            logW("⚠️ No images matched stack trace (total: %d)!", allLoadedImages.count)
        }
        
        data["crash.platform"] = AnyEncodable("iOS")
        
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
        data["action.status"] = AnyEncodable("CRASH")
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
        
        // Add mapping file identifiers for deobfuscation
        let frameworkBundle = Bundle(for: BusinessEventsClient.self)
        if let bundleId = frameworkBundle.bundleIdentifier {
            data["crash.bundleId"] = AnyEncodable(bundleId)
        }
        if let version = frameworkBundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            data["crash.version"] = AnyEncodable(version)
        }
        if let build = frameworkBundle.infoDictionary?["CFBundleVersion"] as? String {
            data["crash.build"] = AnyEncodable(build)
        }
        if let uuid = getBinaryUUID() {
            data["crash.uuid"] = AnyEncodable(uuid)
        } else {
            print("❌ crash.uuid is nil - unable to extract framework UUID")
        }
        
        // Collect loaded images and filter by stack trace
        let allLoadedImages = getLoadedImages()
        
        // Filter images to only those referenced in the stack trace
        // Extract stack trace string from AnyEncodable by encoding/decoding
        var stackTrace = ""
        if let stackTraceEncodable = extraAttributes["crash.stackTrace"] {
            // Try to encode and decode to extract the underlying String
            if let jsonData = try? JSONEncoder().encode(stackTraceEncodable),
               let decodedString = try? JSONDecoder().decode(String.self, from: jsonData) {
                stackTrace = decodedString
            }
        }
        
        let filteredImages = filterImagesByStackTrace(allImages: allLoadedImages, stackTrace: stackTrace)
        
        if !filteredImages.isEmpty {
            data["crash.loaded_images"] = AnyEncodable(filteredImages)
        } else {
            // Warning: No images matched for symbolication
            print("⚠️ No images matched stack trace for crash symbolication")
        }
        
        data["crash.platform"] = AnyEncodable("iOS")
        
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
        
        try sendSync(event: event, config: cfg)
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
        var timeoutTimer: Timer?
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
        logD("sendSync: Starting synchronous network request to %@", config.endpoint.absoluteString)
        
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

        logD("sendSync: Request configured, creating URLSession task...")
        
        // Use semaphore to make synchronous request
        let semaphore = DispatchSemaphore(value: 0)
        var responseCode: Int = -1
        var responseError: Error?
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                responseError = error
            } else {
                responseCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            }
            semaphore.signal()
        }
        
        task.resume()
        
        // Wait for completion with timeout
        let timeout = semaphore.wait(timeout: .now() + 10.0)
        
        if timeout == .timedOut {
            logE("sendSync: Request TIMED OUT")
            task.cancel()
            throw ClientError.badResponse(-1)
        }
        
        if let error = responseError {
            logE("sendSync: Network error = %@", error.localizedDescription)
            throw error
        }
        
        guard responseCode == 202 else {
            logE("sendSync: Bad response code = %d", responseCode)
            throw ClientError.badResponse(responseCode)
        }
        
        logI("sendSync: Successfully sent (202 Accepted)")
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
    public func remove(id: UUID) -> BusinessEventsClient.ActionContext? { 
        q.sync { 
            guard var ctx = dict.removeValue(forKey: id) else { return nil }
            ctx.timeoutTimer?.invalidate()
            ctx.timeoutTimer = nil
            return ctx
        } 
    }
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

// MARK: - Binary UUID Extraction

private func getLoadedImages() -> [[String: String]] {
    var images: [[String: String]] = []
    
    #if arch(x86_64) || arch(arm64)
    let imageCount = _dyld_image_count()
    
    for i in 0..<imageCount {
        guard let imageName = _dyld_get_image_name(i) else { continue }
        let imagePath = String(cString: imageName)
        let header = _dyld_get_image_header(i)
        
        // Get the base address (actual load address in memory)
        let baseAddress = UInt(bitPattern: header)
        let hexAddress = String(format: "0x%llx", baseAddress)
        
        // Extract just the image name (last path component)
        let imageNameOnly = (imagePath as NSString).lastPathComponent
        
        images.append([
            "name": imageNameOnly,
            "path": imagePath,
            "base_address": hexAddress
        ])
    }
    
    #else
    print("⚠️ getLoadedImages() not supported on this architecture")
    #endif
    
    return images
}

/// Filter loaded images to only those referenced in the stack trace
/// This reduces payload size and focuses on relevant libraries for crash symbolication
private func filterImagesByStackTrace(allImages: [[String: String]], stackTrace: String) -> [[String: String]] {
    guard !stackTrace.isEmpty else {
        return allImages
    }
    
    // Extract library names from stack trace
    // Stack trace format: "3   PaymentLibrary      0x0000000104d0b620 PaymentLibrary + 13856"
    var referencedLibraries = Set<String>()
    let lines = stackTrace.components(separatedBy: .newlines)
    
    for line in lines {
        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if components.count >= 2 {
            // Second component is the library name
            let libraryName = components[1]
            referencedLibraries.insert(libraryName)
        }
    }
    
    // Filter images to only those whose names appear in the stack trace
    let filtered = allImages.filter { image in
        guard let imageName = image["name"] else { return false }
        return referencedLibraries.contains(imageName)
    }
    
    // Log warning if no matches found (may indicate symbolication issues)
    if filtered.isEmpty && !referencedLibraries.isEmpty {
        print("⚠️ No image matches found for stack trace symbolication")
    }
    
    return filtered
}

private func getBinaryUUID() -> String? {
    #if arch(x86_64) || arch(arm64)
    
    // Use Objective-C runtime to get the exact image (dylib/framework) where BusinessEventsClient class is defined
    guard let imageName = class_getImageName(BusinessEventsClient.self) else {
        print("❌ class_getImageName returned nil for BusinessEventsClient")
        return nil
    }
    
    let imagePath = String(cString: imageName)
    
    // Get the mach header for this specific image
    let imageCount = _dyld_image_count()
    var targetHeader: UnsafePointer<mach_header>?
    
    for i in 0..<imageCount {
        if let loadedImageName = _dyld_get_image_name(i),
           String(cString: loadedImageName) == imagePath {
            targetHeader = _dyld_get_image_header(i)
            break
        }
    }
    
    guard let header64 = targetHeader?.withMemoryRebound(to: mach_header_64.self, capacity: 1, { $0 }) else {
        print("❌ Could not find mach_header for framework image")
        return nil
    }
    
    // Navigate through load commands to find LC_UUID
    var currentCommand = UnsafeRawPointer(header64).advanced(by: MemoryLayout<mach_header_64>.size)
    
    for _ in 0..<header64.pointee.ncmds {
        let loadCommand = currentCommand.assumingMemoryBound(to: load_command.self)
        
        // LC_UUID = 0x1b
        if loadCommand.pointee.cmd == 0x1b {
            // uuid_command structure: load_command (8 bytes) + uuid (16 bytes)
            let uuidBytes = currentCommand.advanced(by: MemoryLayout<load_command>.size).assumingMemoryBound(to: UInt8.self)
            
            let uuid = (0..<16).map { String(format: "%02X", uuidBytes[$0]) }
            
            // Format as: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            let formattedUUID = uuid.enumerated().map { index, hex in
                let needsDash = [4, 6, 8, 10].contains(index)
                return (needsDash ? "-" : "") + hex
            }.joined()
            
            return formattedUUID
        }
        
        currentCommand = currentCommand.advanced(by: Int(loadCommand.pointee.cmdsize))
    }
    
    print("❌ LC_UUID load command not found in PaymentLibrary.framework binary")
    #else
    print("❌ getBinaryUUID() only supports x86_64 and arm64 architectures")
    #endif
    return nil
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

