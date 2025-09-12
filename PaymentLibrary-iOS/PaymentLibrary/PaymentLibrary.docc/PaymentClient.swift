// PaymentClient.swift — dentro do módulo PaymentLibrary

import Foundation
import os.log
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

    // Singleton
    public static var shared: PaymentClient {
        guard let instance = instance else {
            fatalError("PaymentClient not initialized. Call getInstance(baseUrl:) first.")
        }
        return instance
    }
    private static var instance: PaymentClient?

    private let baseUrl: String

    /// Inicializa (uma vez) o singleton
    @discardableResult
    public static func getInstance(baseUrl: String) -> PaymentClient {
        if let i = instance { return i }
        let i = PaymentClient(baseUrl: baseUrl)
        instance = i
        return i
    }

    private init(baseUrl: String) {
        self.baseUrl = baseUrl
        #if canImport(UIKit)
        os_log("PaymentClient init iOS %@", type: .info, UIDevice.current.systemVersion)
        #else
        os_log("PaymentClient init", type: .info)
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
    ) {
        os_log("Starting payment process.", type: .info)

        if crashStatus {
            os_log("Simulating crash.", type: .error)
            fatalError("Simulated Payment Library Crash")
        }

        Task {
            await executePayment(
                amount: amount,
                creditCardNumber: creditCardNumber,
                vendorName: vendorName,
                vendorId: vendorId,
                callback: callback
            )
        }
    }

    public func cancelPayment(
        transactionId: String,
        callback: CancellationCallback
    ) {
        Task { await executeCancellation(transactionId: transactionId, callback: callback) }
    }

    // MARK: - Internals
    private func executePayment(
        amount: Double,
        creditCardNumber: String,
        vendorName: String,
        vendorId: String,
        callback: PaymentCallback
    ) async {
        if baseUrl == "TEST_ONLY" {
            if amount > 0 {
                DispatchQueue.main.async {
                    callback.onPaymentSuccess(transactionId: UUID().uuidString)
                }
            } else {
                DispatchQueue.main.async {
                    callback.onPaymentFailure(error: "Amount must be positive.")
                }
            }
            return
        }

        guard let url = URL(string: baseUrl + "/receive_payment") else {
            DispatchQueue.main.async {
                callback.onPaymentFailure(error: "Invalid base URL")
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
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async {
                    callback.onPaymentFailure(error: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                return
            }
            let decoded = try JSONDecoder().decode(PaymentResponse.self, from: data)
            DispatchQueue.main.async { callback.onPaymentSuccess(transactionId: decoded.transactionId) }
        } catch {
            DispatchQueue.main.async { callback.onPaymentFailure(error: error.localizedDescription) }
        }
    }

    private func executeCancellation(
        transactionId: String,
        callback: CancellationCallback
    ) async {
        if baseUrl == "TEST_ONLY" {
            DispatchQueue.main.async {
                transactionId.isEmpty ? callback.onCancellationFailure(error: "Empty transactionId")
                                      : callback.onCancellationSuccess()
            }
            return
        }

        guard let url = URL(string: baseUrl + "/cancel_payment") else {
            DispatchQueue.main.async { callback.onCancellationFailure(error: "Invalid base URL") }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PaymentCancellationRequest(transactionId: transactionId)

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async {
                    callback.onCancellationFailure(error: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
                return
            }
            DispatchQueue.main.async { callback.onCancellationSuccess() }
        } catch {
            DispatchQueue.main.async { callback.onCancellationFailure(error: error.localizedDescription) }
        }
    }
}
