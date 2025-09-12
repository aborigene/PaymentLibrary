import Foundation
import os.log



// Assuming DynatraceDestination is available in this module or imported
// NOTE: You must ensure the DynatraceDestination class is correctly imported or defined
// in your project structure for the code below to compile successfully.

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Callbacks (públicos)
public protocol PaymentCallback: AnyObject {
    func onPaymentSuccess(transactionId: String)
    func onPaymentFailure(error: String)
}

public protocol CancellationCallback: AnyObject {
    func onCancellationSuccess()
    func onCancellationFailure(error: String)
}

// MARK: - Modelos internos (não expostos)
struct PaymentRequest: Encodable {
    let amount: Double
    let creditCardNumber: String
    let vendorName: String
    let vendorId: String
}

struct PaymentResponse: Decodable {
    let transactionId: String
}

struct PaymentCancellationRequest: Encodable {
    let transactionId: String
}

// MARK: - Cliente
public final class PaymentClient {

    // Logger as a static property to avoid module interface verification issues
    private static let logger = SwiftyBeaver.self

    // Singleton
    public static var shared: PaymentClient {
        guard let instance = instance else {
            // Log call updated to use logger
            PaymentClient.logger.error("PaymentClient not initialized. Call getInstance(baseUrl:) first.")
            fatalError("PaymentClient not initialized. Call getInstance(baseUrl:) first.")
        }
        return instance
    }
    private static var instance: PaymentClient?

    private let baseUrl: String
    
    private let bizEventsURL: URL = URL(string: "\(Secrets.dynatraceTenant)/api/v2/bizevents/ingest")!
    private let bizEventToken: String = Secrets.dynatraceBusinessEventIngestToken
    private let bizEventProvider: String = "PaymentLibrary"
    
    public func configureBusinessEvents(endpoint: URL, auth: BusinessEventsClient.Auth, eventProvider: String) {
        BusinessEventsClient.shared.configure(
            .init(
                endpoint: endpoint,
                auth: auth,
                eventProvider: eventProvider,
                defaultEventType: "com.paymentlibrary.transaction",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                deviceInfo: UIDevice.current.systemName + " " + UIDevice.current.systemVersion
            )
        )
    }
    
    // --- SwiftyBeaver/Dynatrace Log Ingest Configuration ---
    // Using static constants for configuration
    private static let logIngestEndpoint = "\(Secrets.dynatraceTenant)/api/v2/logs/ingest"
    private static let logIngestApiToken = Secrets.dynatraceLogIngestToken
    private static let logIngestAppName = "Cielo SDK"

    // Encapsulate logging configuration in a static method
    private static func configureLogging() {
        let logger = PaymentClient.logger
        // Only configure if not already done (Checking destinations count is sufficient)
        guard logger.destinations.isEmpty else { return }

        // REMOVED ConsoleDestination setup to simplify module graph.
        
        // NOTE: DynatraceDestination must be accessible (i.e., imported or defined locally).
        let dynatraceDestination = DynatraceDestination(
            endpoint: logIngestEndpoint,
            apiToken: logIngestApiToken,
            appName: logIngestAppName
        )
        logger.addDestination(dynatraceDestination)
    }


    /// Inicializa (uma vez) o singleton
    @discardableResult
    public static func getInstance(baseUrl: String) -> PaymentClient {
        if let i = instance { return i }
        // Call configuration here
        PaymentClient.configureLogging()
        let i = PaymentClient(baseUrl: baseUrl)
        instance = i
        return i
    }

    private init(baseUrl: String) {
        self.baseUrl = baseUrl
        
        // Configure other services
        configureBusinessEvents(endpoint: bizEventsURL, auth: .apiToken(bizEventToken), eventProvider: bizEventProvider)
        CrashReporterKit.shared.enable()
        
        let attributes = [
            "payment.amount": AnyEncodable(20)
        ]
        BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions.init(name: "myAction", attributes: attributes, parentActionId: nil))
        
        // Log call updated to use logger
        #if canImport(UIKit)
        PaymentClient.logger.info("PaymentClient init iOS \(UIDevice.current.systemVersion)")
        #else
        PaymentClient.logger.info("PaymentClient init")
        #endif
    }
    

    // MARK: - API pública
    public func receivePayment(
        amount: Double,
        creditCardNumber: String,
        vendorName: String,
        vendorId: String,
        callback: PaymentCallback,
        crashStatus: Bool
    ) async throws {
        try await BusinessEventsClient.shared.withAction(
            name: "receivePayment",
            attributes: [
                "payment.amount": AnyEncodable(amount),
                "payment.creditCardNumber": AnyEncodable(creditCardNumber),
                "payment.vendorName": AnyEncodable(vendorName),
                "payment.vendorId": AnyEncodable(vendorId)
            ]
        ) {
            // Log call updated to use logger
            PaymentClient.logger.info("Starting payment process for amount \(amount).")

            if crashStatus {
                PaymentClient.logger.error("Simulating crash on purpose.")
                fatalError("Simulated Payment Library Crash")
            }

            Task {
                PaymentClient.logger.info("Calling executePayment asynchronously.")
                try await executePayment(
                    amount: amount,
                    creditCardNumber: creditCardNumber,
                    vendorName: vendorName,
                    vendorId: vendorId,
                    callback: callback
                )
                PaymentClient.logger.verbose("Starting to sleep...")
                let randomNumber: UInt32 = UInt32(Int.random(in: 700...3000))
                sleep(randomNumber)
                PaymentClient.logger.verbose("Finished sleeping.")
                
            }
        }
    }

    public func cancelPayment(
        transactionId: String,
        callback: CancellationCallback
    ) {
        // Log call updated to use logger
        PaymentClient.logger.info("Attempting to cancel payment for transaction ID: \(transactionId)")
        Task { await executeCancellation(transactionId: transactionId, callback: callback) }
    }

    // MARK: - Internals
    private func executePayment(
        amount: Double,
        creditCardNumber: String,
        vendorName: String,
        vendorId: String,
        callback: PaymentCallback
    ) async throws{
        try await BusinessEventsClient.shared.withAction(
            name: "executePayment",
            attributes: [
                "payment.amount": AnyEncodable(amount),
                "payment.creditCardNumber": AnyEncodable(creditCardNumber),
                "payment.vendorName": AnyEncodable(vendorName),
                "payment.vendorId": AnyEncodable(vendorId)
            ]
        ) {
            // Log calls updated to use logger
            PaymentClient.logger.debug("Inside executePayment method implementation.")
            PaymentClient.logger.verbose("Starting to sleep for latency simulation...")
            let randomNumber: UInt32 = UInt32(Int.random(in: 700...3000))
            sleep(randomNumber)
            PaymentClient.logger.verbose("Finished sleeping.")
            
            if baseUrl == "TEST_ONLY" {
                if amount > 0 {
                    DispatchQueue.main.async {
                        callback.onPaymentSuccess(transactionId: UUID().uuidString)
                        PaymentClient.logger.info("Payment successful in TEST_ONLY mode.")
                    }
                } else {
                    DispatchQueue.main.async {
                        callback.onPaymentFailure(error: "Amount must be positive.")
                        PaymentClient.logger.warning("Payment failed in TEST_ONLY mode: Amount not positive.")
                    }
                }
                return
            }
            
            guard let url = URL(string: baseUrl + "/receive_payment") else {
                DispatchQueue.main.async {
                    callback.onPaymentFailure(error: "Invalid base URL")
                    PaymentClient.logger.error("Failed to construct valid URL for payment.")
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = PaymentRequest(amount: amount, creditCardNumber: creditCardNumber, vendorName: vendorName, vendorId: vendorId)
            
            do {
                request.httpBody = try JSONEncoder().encode(body)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    DispatchQueue.main.async {
                        callback.onPaymentFailure(error: "HTTP \(statusCode)")
                        PaymentClient.logger.error("Payment API call failed with HTTP status code: \(statusCode)")
                    }
                    return
                }
                let decoded = try JSONDecoder().decode(PaymentResponse.self, from: data)
                DispatchQueue.main.async {
                    callback.onPaymentSuccess(transactionId: decoded.transactionId)
                    PaymentClient.logger.info("Payment completed. Transaction ID: \(decoded.transactionId)")
                }
            } catch {
                DispatchQueue.main.async {
                    callback.onPaymentFailure(error: error.localizedDescription)
                    PaymentClient.logger.error("Payment network request failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func executeCancellation(
        transactionId: String,
        callback: CancellationCallback
    ) async {
        if baseUrl == "TEST_ONLY" {
            DispatchQueue.main.async {
                if transactionId.isEmpty {
                    callback.onCancellationFailure(error: "Empty transactionId")
                    PaymentClient.logger.warning("Cancellation failed in TEST_ONLY mode: Empty ID.")
                } else {
                    callback.onCancellationSuccess()
                    PaymentClient.logger.info("Cancellation successful in TEST_ONLY mode.")
                }
            }
            return
        }

        guard let url = URL(string: baseUrl + "/cancel_payment") else {
            DispatchQueue.main.async {
                callback.onCancellationFailure(error: "Invalid base URL")
                PaymentClient.logger.error("Failed to construct valid URL for cancellation.")
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PaymentCancellationRequest(transactionId: transactionId)

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    callback.onCancellationFailure(error: "HTTP \(statusCode)")
                    PaymentClient.logger.error("Cancellation API call failed with HTTP status code: \(statusCode)")
                }
                return
            }
            DispatchQueue.main.async {
                callback.onCancellationSuccess()
                PaymentClient.logger.info("Cancellation completed successfully.")
            }
        } catch {
            DispatchQueue.main.async {
                callback.onCancellationFailure(error: error.localizedDescription)
                PaymentClient.logger.error("Cancellation network request failed: \(error.localizedDescription)")
            }
        }
    }
}
