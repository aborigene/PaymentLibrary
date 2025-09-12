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
// - Supports parent/child cascades via W3C traceparent (same trace-id, parent span)
//
// Requirements:
//  - Create an API token with scope `bizevents.ingest` OR use OAuth Bearer.
//  - Endpoint (classic env): https://{env}.live.dynatrace.com/api/v2/bizevents/ingest
//  - Content-Type (CloudEvents): application/cloudevent+json
//
// Notes:
//  - We include both explicit action fields (action.id, action.parentId, duration) and a
//    proper traceparent so you can analyze cascades by either approach.
//
//  - If you prefer pure JSON instead of CloudEvents, switch the encoder at the bottom.
//
import Foundation
import Security
import os.log

// MARK: - Public API

public final class BusinessEventsClient {
    public static let shared = BusinessEventsClient()

    public enum Auth {
        case apiToken(String)      // "Authorization: Api-Token <token>"
        case bearer(String)        // "Authorization: Bearer <token>"
    }

    public struct Config {
        public var endpoint: URL                   // .../api/v2/bizevents/ingest
        public var auth: Auth
        public var eventProvider: String          // maps to CloudEvents `source` (→ event.provider)
        public var defaultEventType: String       // e.g. "com.unitedgames.user.action"
        public var appVersion: String?            // optional meta
        public var deviceInfo: String?            // optional meta
        public init(endpoint: URL,
                    auth: Auth,
                    eventProvider: String,
                    defaultEventType: String,
                    appVersion: String? = nil,
                    deviceInfo: String? = nil) {
            self.endpoint = endpoint
            self.auth = auth
            self.eventProvider = eventProvider
            self.defaultEventType = defaultEventType
            self.appVersion = appVersion
            self.deviceInfo = deviceInfo
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
    }

    // Start an action; returns actionId you will use to end it
    @discardableResult
    public func beginAction(_ opts: BeginOptions) -> UUID {
        guard let cfg = config else {
            assertionFailure("BusinessEventsClient not configured. Call configure(_:) first.")
            return UUID()
        }
        let now = Date()
        // If parent exists, re-use its traceId, otherwise create a new one
        var traceId = Self.randomTraceId()
        var parentSpan: String? = nil
        if let parentId = opts.parentActionId, let parent = store.lookup(id: parentId) {
            traceId = parent.traceId
            parentSpan = parent.spanId
        }
        let ctx = ActionContext(
            id: UUID(),
            name: opts.name,
            startedAt: now,
            attributes: opts.attributes,
            parentActionId: opts.parentActionId,
            traceId: traceId,
            spanId: Self.randomSpanId(),
            parentSpanId: parentSpan,
            eventType: cfg.defaultEventType
        )
        store.insert(ctx)
        return ctx.id
    }

    // Finish and send immediately
    public func endAction(_ actionId: UUID,
                          status: String = "OK",
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
        if let v = config?.appVersion { data["app.version"] = AnyEncodable(v) }
        if let d = config?.deviceInfo { data["device.info"] = AnyEncodable(d) }

        let event = CloudEvent(
            specversion: "1.0",
            id: UUID().uuidString,
            source: cfg.eventProvider, // becomes event.provider
            type: ctx.eventType,       // becomes event.type
            time: ISO8601DateFormatter.dtTime.string(from: finishedAt),
            traceparent: Self.buildTraceparent(traceId: ctx.traceId, spanId: ctx.spanId),
            data: data
        )

        try await send(event: event, config: cfg)
        os_log("Executo end action")
    }
    

    // Convenience wrapper that auto-finalizes
    public func withAction<T>(name: String,
                              attributes: [String: AnyEncodable] = [:],
                              parentActionId: UUID? = nil,
                              body: () async throws -> T) async throws -> T {
        let id = beginAction(.init(name: name, attributes: attributes, parentActionId: parentActionId))
        do {
            let result = try await body()
            try await endAction(id, status: "OK")
            //let log =
            os_log("Action name: \(name)")
            // os_log("Attributes: \(name)")
            return result
        } catch {
            try? await endAction(id, status: "ERROR", error: String(describing: error))
            throw error
        }
    }

    // MARK: - Internals

    public enum ClientError: Error { case notConfigured, unknownAction, badResponse(Int) }

    fileprivate struct ActionContext {
        let id: UUID
        let name: String
        let startedAt: Date
        let attributes: [String: AnyEncodable]
        let parentActionId: UUID?
        let traceId: String
        let spanId: String
        let parentSpanId: String?
        let eventType: String
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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.badResponse(code)
        }
    }

    // MARK: - Trace helpers

    private static func buildTraceparent(traceId: String, spanId: String, sampled: Bool = true) -> String {
        let flags = sampled ? "01" : "00"
        return "00-\(traceId)-\(spanId)-\(flags)"
    }

    private static func randomTraceId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomSpanId() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CloudEvents payload

private struct CloudEvent: Encodable {
    let specversion: String          // "1.0"
    let id: String                   // event id
    let source: String               // → event.provider
    let type: String                 // → event.type
    let time: String?                // RFC3339/ISO8601
    let traceparent: String?         // W3C trace context (optional but useful)
    let data: [String: AnyEncodable] // business payload
}

// MARK: - In-memory store (thread-safe)

private final class InMemoryStore {
    private var dict: [UUID: BusinessEventsClient.ActionContext] = [:]
    private let q = DispatchQueue(label: "biz.store")
    public func insert(_ ctx: BusinessEventsClient.ActionContext) { q.sync { dict[ctx.id] = ctx } }
    public func lookup(id: UUID) -> BusinessEventsClient.ActionContext? { q.sync { dict[id] } }
    public func remove(id: UUID) -> BusinessEventsClient.ActionContext? { q.sync { dict.removeValue(forKey: id) } }
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
import UIKit

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
    try await BusinessEventsClient.shared.endAction(child, status: "OK")
    try await BusinessEventsClient.shared.endAction(parent, status: "OK")
}
*/

