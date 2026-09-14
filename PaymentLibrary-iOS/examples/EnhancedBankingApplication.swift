//
//  EnhancedBankingApplication.swift  
//  PaymentLibrary iOS Enhanced Integration
//
//  This example demonstrates comprehensive device metadata collection
//  and enhanced business events tracking for iOS applications.
//

import Foundation
import UIKit
import PaymentLibrary
import CoreTelephony
import Network

// MARK: - Enhanced App Delegate

@main
class EnhancedBankingAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        print("Starting Enhanced Banking Application for iOS...")
        configureDynatraceIntegration()
        testDeviceMetadataCollection()
        
        return true
    }
    
    /// Configure Dynatrace integration with enhanced device metadata collection
    private func configureDynatraceIntegration() {
        // Configure DynatraceLogger for log ingestion
        DynatraceLogger.configure(
            endpoint: "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest",
            apiToken: "dt0c01.YOUR_LOG_INGEST_TOKEN",
            appName: "Enhanced-Banking-iOS"
        )
        
        // Configure BusinessEventsClient with automatic device metadata collection
        // This method automatically collects comprehensive device information
        BusinessEventsClient.shared.configureWithDeviceMetadata(
            endpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest")!,
            auth: .apiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
            eventProvider: "com.yourbank.enhanced.ios",
            defaultEventType: "com.yourbank.enhanced.user.action",
            appVersion: getAppVersion()
        )
        
        DynatraceLogger.info("Enhanced Banking App initialized with comprehensive device metadata", category: "EnhancedBankingApp")
    }
    
    /// Test device metadata collection by sending a sample event
    private func testDeviceMetadataCollection() {
        Task {
            do {
                // Create a sample business event to test metadata collection
                let testActionId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                    name: "app_initialization",
                    attributes: [
                        "initialization_type": AnyEncodable("cold_start"),
                        "app_version": AnyEncodable(getAppVersion()),
                        "device_info": AnyEncodable("\(UIDevice.current.model) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))")
                    ]
                ))
                
                // Simulate some initialization work
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                // End the action - this will automatically include all collected device metadata
                try await BusinessEventsClient.shared.endAction(
                    testActionId,
                    status: "SUCCESS",
                    extraAttributes: [
                        "initialization_duration_ms": AnyEncodable(100),
                        "features_enabled": AnyEncodable(["payment", "transfer", "balance_check"]),
                        "network_available": AnyEncodable(isNetworkAvailable())
                    ]
                )
                
                print("✅ Device metadata test event sent successfully")
                
            } catch {
                print("❌ Failed to send device metadata test event: \(error.localizedDescription)")
            }
        }
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    private func isNetworkAvailable() -> Bool {
        // Simple network availability check
        let networkInfo = CTTelephonyNetworkInfo()
        return networkInfo.currentRadioAccessTechnology != nil || 
               NetworkReachability.isConnectedToNetwork()
    }
}

// MARK: - Enhanced Payment View Controller

class EnhancedPaymentViewController: UIViewController {
    
    private var paymentClient: PaymentClient!
    private let sessionStartTime = Date()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize PaymentClient
        paymentClient = PaymentClient(baseURL: "https://api.yourbank.com")
        
        setupEnhancedUI()
        trackScreenView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        trackUserEngagement()
    }
    
    // MARK: - UI Setup
    
    private func setupEnhancedUI() {
        view.backgroundColor = .systemBackground
        title = "Enhanced Payment"
        
        let payButton = UIButton(type: .system)
        payButton.setTitle("Process Enhanced Payment", for: .normal)
        payButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        payButton.backgroundColor = .systemBlue
        payButton.setTitleColor(.white, for: .normal)
        payButton.layer.cornerRadius = 12
        payButton.addTarget(self, action: #selector(processEnhancedPayment), for: .touchUpInside)
        
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payButton)
        
        NSLayoutConstraint.activate([
            payButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            payButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            payButton.widthAnchor.constraint(equalToConstant: 280),
            payButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - Enhanced Tracking Methods
    
    private func trackScreenView() {
        Task {
            let screenViewId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "screen_view",
                attributes: [
                    "screen_name": AnyEncodable("enhanced_payment"),
                    "screen_class": AnyEncodable("EnhancedPaymentViewController"),
                    "navigation_source": AnyEncodable("main_menu"),
                    "user_session_id": AnyEncodable(UUID().uuidString)
                ]
            ))
            
            // Track screen view duration when view disappears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task {
                    try? await BusinessEventsClient.shared.endAction(
                        screenViewId,
                        status: "VIEWED",
                        extraAttributes: [
                            "view_duration_ms": AnyEncodable(500),
                            "screen_interactions": AnyEncodable(1)
                        ]
                    )
                }
            }
        }
    }
    
    private func trackUserEngagement() {
        Task {
            let engagementId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "user_engagement",
                attributes: [
                    "engagement_type": AnyEncodable("screen_focus"),
                    "previous_screen": AnyEncodable("dashboard"),
                    "session_depth": AnyEncodable(3)
                ]
            ))
            
            try? await BusinessEventsClient.shared.endAction(
                engagementId,
                status: "ENGAGED"
            )
        }
    }
    
    // MARK: - Enhanced Payment Processing
    
    @objc private func processEnhancedPayment() {
        Task {
            await performEnhancedPaymentFlow()
        }
    }
    
    private func performEnhancedPaymentFlow() async {
        do {
            // Begin payment session with enhanced tracking
            let sessionId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "payment_session",
                attributes: [
                    "session_type": AnyEncodable("card_payment"),
                    "entry_point": AnyEncodable("payment_button"),
                    "user_agent": AnyEncodable("Enhanced-Banking-iOS"),
                    "session_id": AnyEncodable(UUID().uuidString)
                ]
            ))
            
            // Begin specific payment processing
            let paymentId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "process_card_payment",
                attributes: [
                    "amount": AnyEncodable(89.99),
                    "currency": AnyEncodable("USD"),
                    "payment_method": AnyEncodable("apple_pay"),
                    "merchant": AnyEncodable("Premium Coffee Roasters"),
                    "location": AnyEncodable("New York, NY")
                ],
                parentActionId: sessionId
            ))
            
            // Add device context tracking
            let deviceContextId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "collect_device_context",
                attributes: [
                    "context_type": AnyEncodable("payment_security"),
                    "collection_method": AnyEncodable("enhanced_metadata")
                ],
                parentActionId: paymentId
            ))
            
            // Collect additional real-time device context
            let currentMetadata = DeviceMetadataCollector.collectMetadata()
            
            try await BusinessEventsClient.shared.endAction(
                deviceContextId,
                status: "SUCCESS",
                extraAttributes: [
                    "metadata_fields_collected": AnyEncodable(25),
                    "network_type": AnyEncodable(currentMetadata.networkType),
                    "battery_level": AnyEncodable(currentMetadata.batteryLevel),
                    "thermal_state": AnyEncodable(currentMetadata.thermalState)
                ]
            )
            
            // Simulate payment processing with network calls
            let networkCallId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "payment_api_call",
                attributes: [
                    "endpoint": AnyEncodable("/api/v3/payments/process"),
                    "method": AnyEncodable("POST"),
                    "request_size_bytes": AnyEncodable(1024),
                    "encryption": AnyEncodable("TLS_1.3")
                ],
                parentActionId: paymentId
            ))
            
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            
            // Simulate payment result
            let paymentResult = PaymentResult(
                success: true,
                transactionId: "TXN_\(UUID().uuidString.prefix(8))",
                authCode: "AUTH_\(Int.random(in: 100000...999999))",
                errorMessage: nil,
                processingTimeMs: 1500,
                networkCallCount: 3,
                retryCount: 0
            )
            
            // End network call tracking
            try await BusinessEventsClient.shared.endAction(
                networkCallId,
                status: paymentResult.success ? "SUCCESS" : "ERROR",
                extraAttributes: [
                    "response_code": AnyEncodable(200),
                    "response_size_bytes": AnyEncodable(512),
                    "server_processing_time_ms": AnyEncodable(800),
                    "network_latency_ms": AnyEncodable(45)
                ]
            )
            
            // End payment processing with detailed results
            try await BusinessEventsClient.shared.endAction(
                paymentId,
                status: paymentResult.success ? "SUCCESS" : "ERROR",
                error: paymentResult.errorMessage,
                extraAttributes: [
                    "transaction_id": AnyEncodable(paymentResult.transactionId),
                    "authorization_code": AnyEncodable(paymentResult.authCode),
                    "processing_time_ms": AnyEncodable(paymentResult.processingTimeMs),
                    "network_calls": AnyEncodable(paymentResult.networkCallCount),
                    "retry_count": AnyEncodable(paymentResult.retryCount),
                    "payment_processor": AnyEncodable("Stripe"),
                    "fraud_score": AnyEncodable(0.12),
                    "risk_level": AnyEncodable("low")
                ]
            )
            
            // End payment session with comprehensive summary
            let sessionDuration = Int(Date().timeIntervalSince(sessionStartTime) * 1000)
            try await BusinessEventsClient.shared.endAction(
                sessionId,
                status: "COMPLETED",
                extraAttributes: [
                    "session_duration_ms": AnyEncodable(sessionDuration),
                    "screens_visited": AnyEncodable(["dashboard", "payment_form", "confirmation"]),
                    "user_actions": AnyEncodable(4),
                    "conversion_funnel_step": AnyEncodable("completed"),
                    "payment_success_rate": AnyEncodable(1.0)
                ]
            )
            
            // Show success message
            await MainActor.run {
                showSuccessAlert(transactionId: paymentResult.transactionId)
            }
            
            DynatraceLogger.info("Enhanced payment flow completed successfully with full device metadata", category: "EnhancedPaymentViewController")
            
        } catch {
            DynatraceLogger.error("Enhanced payment flow failed: \(error.localizedDescription)", category: "EnhancedPaymentViewController")
            
            await MainActor.run {
                showErrorAlert(error: error)
            }
        }
    }
    
    // MARK: - UI Feedback
    
    private func showSuccessAlert(transactionId: String) {
        let alert = UIAlertController(
            title: "Payment Successful! 🎉", 
            message: "Transaction ID: \(transactionId)\n\nYour payment has been processed with enhanced device metadata for optimal security and monitoring.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Great!", style: .default))
        present(alert, animated: true)
    }
    
    private func showErrorAlert(error: Error) {
        let alert = UIAlertController(
            title: "Payment Error",
            message: "An error occurred: \(error.localizedDescription)\n\nDevice metadata has been collected for troubleshooting.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
            Task { await self.performEnhancedPaymentFlow() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
}

// MARK: - Enhanced Payment Result

struct PaymentResult {
    let success: Bool
    let transactionId: String
    let authCode: String
    let errorMessage: String?
    let processingTimeMs: Int
    let networkCallCount: Int
    let retryCount: Int
}

// MARK: - Network Reachability Helper

class NetworkReachability {
    static func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return isReachable && !needsConnection
    }
}

// MARK: - Enhanced Device Metadata Demo

extension EnhancedPaymentViewController {
    
    /// Demonstrate manual device metadata collection and usage
    private func demonstrateDeviceMetadata() {
        print("\n=== Enhanced Device Metadata Collection Demo ===")
        
        // Collect comprehensive metadata
        let metadata = DeviceMetadataCollector.collectMetadata()
        
        print("📱 Device Information:")
        print("   Model: \(metadata.deviceModel)")
        print("   OS: \(metadata.osVersion)")
        print("   Screen: \(metadata.screenBounds) (\(metadata.screenScale)x scale)")
        print("   Memory: \(metadata.memoryTotal / 1_000_000) MB total")
        print("   Storage: \(metadata.storageAvailable / 1_000_000_000) GB available")
        
        print("\n🌐 Network Information:")
        print("   Type: \(metadata.networkType)")
        print("   Carrier: \(metadata.carrierName ?? "N/A")")
        print("   IP: \(metadata.deviceIpAddress ?? "N/A")")
        
        print("\n🔋 System Status:")
        print("   Battery: \(Int(metadata.batteryLevel * 100))% (\(metadata.batteryState))")
        print("   Thermal: \(metadata.thermalState)")
        print("   Low Power Mode: \(metadata.isLowPowerModeEnabled)")
        
        print("\n🌍 Context:")
        print("   Locale: \(metadata.deviceLocale)")
        print("   Timezone: \(metadata.deviceTimezone)")
        print("   Processor Count: \(metadata.processorCount)")
        
        // Convert to event attributes for business events
        let eventAttributes = DeviceMetadataCollector.toEventAttributes(metadata)
        print("\n📊 Event Attributes: \(eventAttributes.count) fields collected")
        
        print("=== Device Metadata Demo Complete ===\n")
    }
}