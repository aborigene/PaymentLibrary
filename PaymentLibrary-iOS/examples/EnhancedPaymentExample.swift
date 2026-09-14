//
//  EnhancedPaymentExample.swift
//  PaymentLibrary iOS - Real-Time Device Metadata Example
//
//  This example demonstrates the enhanced PaymentLibrary with:
//  1. Automatic session_started business event
//  2. Real-time device metadata collection on each action
//  3. Dynamic metadata tracking (battery, memory, network changes)
//

import Foundation
import UIKit
import PaymentLibrary

// MARK: - Enhanced Payment Example Application

@main
class EnhancedPaymentExampleApp: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        print("🚀 Starting Enhanced Payment Example with Real-Time Metadata")
        
        // Initialize PaymentClient with enhanced device metadata
        // This automatically creates a "session_started" business event
        let paymentClient = PaymentClient.getInstanceWithEnhancedMetadata(
            baseUrl: "https://api.enhanced-bank.com",
            dynatraceEndpoint: URL(string: "https://tenant.live.dynatrace.com/api/v2/bizevents/ingest"),
            dynatraceToken: "dt0c01.ENHANCED_TOKEN",
            eventProvider: "enhanced-payment-ios-app"
        )
        
        print("✅ PaymentClient initialized - session_started event created automatically")
        
        // Simulate some payment operations to demonstrate real-time metadata
        Task {
            await demonstrateEnhancedPaymentFlow(client: paymentClient)
        }
        
        return true
    }
}

// MARK: - Enhanced Payment Flow Demonstration

extension EnhancedPaymentExampleApp {
    
    /// Demonstrates enhanced payment flow with real-time device metadata collection
    private func demonstrateEnhancedPaymentFlow(client: PaymentClient) async {
        
        print("\n📊 Starting Enhanced Payment Flow Demonstration")
        
        // Payment 1: Morning coffee with full device context
        await processEnhancedPayment(
            client: client,
            amount: 4.99,
            merchant: "Morning Coffee Co",
            description: "Morning coffee payment with real-time device tracking"
        )
        
        // Simulate device state changes
        await simulateDeviceStateChanges()
        
        // Payment 2: Lunch purchase with updated device state
        await processEnhancedPayment(
            client: client,
            amount: 24.50,
            merchant: "Healthy Lunch Spot",
            description: "Lunch payment after device state changes"
        )
        
        // Payment 3: Evening purchase with background processing
        await processEnhancedPayment(
            client: client,
            amount: 89.99,
            merchant: "Evening Electronics Store",
            description: "Evening purchase with comprehensive tracking"
        )
        
        print("\n🎉 Enhanced Payment Flow Demonstration Complete")
        await displayMetadataCollectionSummary()
    }
    
    /// Process a payment with enhanced device metadata tracking
    private func processEnhancedPayment(
        client: PaymentClient,
        amount: Double,
        merchant: String,
        description: String
    ) async {
        
        print("\n💳 Processing Enhanced Payment: $\(amount) at \(merchant)")
        
        do {
            // This payment will automatically include:
            // 1. Fresh device metadata at action start
            // 2. Fresh device metadata at action end
            // 3. Real-time changes (battery, memory, network)
            
            await client.receivePayment(
                amount: amount,
                creditCardNumber: "4111111111111111",
                vendorName: merchant,
                vendorId: "vendor_\(merchant.replacingOccurrences(of: " ", with: "_").lowercased())"
            ) { result in
                switch result {
                case .success(let transactionId):
                    print("✅ Payment successful: \(transactionId)")
                    print("   📊 Real-time metadata included:")
                    self.logCurrentDeviceState()
                    
                case .failure(let error):
                    print("❌ Payment failed: \(error)")
                    print("   📊 Error metadata collected for analysis")
                }
            }
            
            // Small delay to allow metadata collection
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
        } catch {
            print("❌ Payment processing error: \(error)")
        }
    }
    
    /// Simulate device state changes between payments
    private func simulateDeviceStateChanges() async {
        print("\n🔄 Simulating device state changes...")
        
        // Simulate some processing that might change device state
        for i in 1...3 {
            print("   Processing batch \(i)/3...")
            
            // Simulate CPU intensive work that might affect thermal state
            let _ = (1...100000).map { $0 * 2 }
            
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        print("   ✅ Device state changes simulated")
    }
    
    /// Log current device state for debugging
    private func logCurrentDeviceState() {
        // Collect dynamic metadata to show current state
        let dynamicMetadata = DeviceMetadataCollector.collectDynamicMetadata()
        
        print("     - Battery Level: \(dynamicMetadata["device.battery_level"] ?? "unknown")")
        print("     - Battery State: \(dynamicMetadata["device.battery_state"] ?? "unknown")")  
        print("     - Memory Available: \(dynamicMetadata["device.memory_available"] ?? "unknown")")
        print("     - Thermal State: \(dynamicMetadata["device.thermal_state"] ?? "unknown")")
        print("     - Network Type: \(dynamicMetadata["network.type"] ?? "unknown")")
        print("     - Collection Time: \(dynamicMetadata["metadata.collection_time"] ?? "unknown")")
    }
    
    /// Display comprehensive metadata collection summary
    private func displayMetadataCollectionSummary() async {
        print("\n📋 Enhanced Metadata Collection Summary")
        print("=" * 50)
        
        // Static metadata (collected once, rarely changes)
        let staticMetadata = DeviceMetadataCollector.collectStaticMetadata()
        print("\n🔧 Static Device Information:")
        print("   Device: \(staticMetadata["device.manufacturer"] ?? "Unknown") \(staticMetadata["device.model"] ?? "Unknown")")
        print("   OS: \(staticMetadata["device.os_version"] ?? "Unknown")")
        print("   Screen: \(staticMetadata["device.screen_bounds"] ?? "Unknown") (\(staticMetadata["device.screen_scale"] ?? "Unknown")x scale)")
        print("   Memory Total: \(staticMetadata["device.memory_total"] ?? "Unknown") bytes")
        print("   Storage Total: \(staticMetadata["device.storage_total"] ?? "Unknown") bytes")
        print("   Processors: \(staticMetadata["device.processor_count"] ?? "Unknown")")
        
        // Dynamic metadata (collected frequently, changes often)
        let dynamicMetadata = DeviceMetadataCollector.collectDynamicMetadata()
        print("\n⚡ Dynamic Device State:")
        print("   Battery: \(dynamicMetadata["device.battery_level"] ?? "Unknown") (\(dynamicMetadata["device.battery_state"] ?? "Unknown"))")
        print("   Memory Available: \(dynamicMetadata["device.memory_available"] ?? "Unknown") bytes")
        print("   Storage Available: \(dynamicMetadata["device.storage_available"] ?? "Unknown") bytes")
        print("   Thermal State: \(dynamicMetadata["device.thermal_state"] ?? "Unknown")")
        print("   Low Power Mode: \(dynamicMetadata["device.low_power_mode"] ?? "Unknown")")
        print("   Network: \(dynamicMetadata["network.type"] ?? "Unknown")")
        print("   IP Address: \(dynamicMetadata["device.ip_address"] ?? "Unknown")")
        
        print("\n🎯 Key Benefits Demonstrated:")
        print("   ✅ Automatic session_started event on app launch")
        print("   ✅ Real-time metadata collection on each payment")
        print("   ✅ Device state tracking (before/after each action)")
        print("   ✅ Dynamic metadata updates (battery, memory, network)")
        print("   ✅ Comprehensive payment context for analytics")
        print("   ✅ Enhanced fraud detection capabilities")
        print("   ✅ Performance monitoring and optimization insights")
        
        print("\n📊 Business Events Created:")
        print("   1. session_started (automatic on PaymentClient init)")
        print("   2. process_payment (x3 with real-time device context)")
        print("   4. Each event includes 25+ device attributes")
        print("   5. Start/end metadata comparison for each action")
        
        print("\n" + "=" * 50)
    }
}

// MARK: - Enhanced PaymentCallback Implementation

class EnhancedPaymentCallback: PaymentCallback {
    
    func onPaymentSuccess(transactionId: String) {
        print("🎉 Enhanced Payment Success!")
        print("   Transaction ID: \(transactionId)")
        print("   📊 Complete device metadata sent to Dynatrace")
        print("   🔍 Real-time fraud detection analysis enabled")
        
        // Log final device state after successful payment
        let finalState = DeviceMetadataCollector.collectDynamicMetadata()
        print("   📱 Final Device State:")
        print("      Battery: \(finalState["device.battery_level"] ?? "unknown")")
        print("      Memory: \(finalState["device.memory_available"] ?? "unknown")")
        print("      Network: \(finalState["network.type"] ?? "unknown")")
    }
    
    func onPaymentFailure(error: String) {
        print("❌ Enhanced Payment Failure")
        print("   Error: \(error)")
        print("   📊 Error context with device metadata sent to Dynatrace")
        print("   🔍 Device state captured for troubleshooting")
        
        // Log device state during failure for debugging
        let errorState = DeviceMetadataCollector.collectDynamicMetadata()
        print("   📱 Error Device State:")
        print("      Battery: \(errorState["device.battery_level"] ?? "unknown")")
        print("      Memory: \(errorState["device.memory_available"] ?? "unknown")")
        print("      Thermal: \(errorState["device.thermal_state"] ?? "unknown")")
        print("      Network: \(errorState["network.type"] ?? "unknown")")
    }
}

// MARK: - Utility Extensions

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

// MARK: - Usage Documentation

/*
 Enhanced PaymentLibrary Usage Example
 
 This example demonstrates the three key enhancements:
 
 1. **Automatic Session Started Event**
    - Created automatically when PaymentClient.getInstanceWithEnhancedMetadata() is called
    - Includes comprehensive device metadata at app launch
    - Provides session context for all subsequent events
 
 2. **Real-Time Device Metadata on All Events**
    - Every business event automatically includes fresh device metadata
    - Metadata collected at both action start and action end
    - Captures device state changes during payment processing
 
 3. **Dynamic Metadata Collection** 
    - Battery level, memory usage, thermal state tracked in real-time
    - Network changes detected and included in events
    - Performance impact monitoring for each payment operation
 
 **Business Events Created:**
 
 ```
 session_started {
   "action.name": "session_started",
   "session.id": "uuid",
   "device.battery_level": 0.90,
   "device.memory_available": 4200000000,
   "network.type": "wifi",
   // ... 25+ device attributes
 }
 
 process_payment {
   "action.name": "process_payment", 
   "payment.amount": 4.99,
   "device.battery_level": 0.89,        // Start state
   "end.device.battery_level": 0.88,    // End state  
   "device.memory_available": 4100000000,
   "end.device.memory_available": 4050000000,
   // ... complete before/after device context
 }
 ```
 
 **Analytics Benefits:**
 - Device performance correlation with payment success rates
 - Battery usage patterns during payment processing
 - Memory optimization opportunities identification
 - Network reliability impact on transaction completion
 - Fraud detection through device behavior analysis
 - User experience optimization based on device capabilities
 */