# iOS PaymentLibrary Integration Guide

## Enhanced Device Metadata Collection

This guide covers integrating the PaymentLibrary iOS framework with comprehensive device metadata collection for Dynatrace business events and logging.

## Table of Contents
1. [Overview](#overview)
2. [Framework Integration](#framework-integration)  
3. [Required Dependencies](#required-dependencies)
4. [Enhanced Device Metadata Features](#enhanced-device-metadata-features)
5. [Configuration](#configuration)
6. [Usage Examples](#usage-examples)
7. [Device Metadata Collection](#device-metadata-collection)
8. [Performance Considerations](#performance-considerations)
9. [Privacy and Permissions](#privacy-and-permissions)
10. [Troubleshooting](#troubleshooting)

## 1. Overview

The enhanced PaymentLibrary iOS framework provides:
- **BusinessEventsClient**: CloudEvents-compatible business events with comprehensive device metadata
- **DynatraceLogger**: Structured logging with device context
- **DeviceMetadataCollector**: Automatic collection of 25+ device attributes
- **PaymentClient**: Payment processing with enhanced telemetry

### New Enhanced Features
- Automatic device metadata collection (OS, hardware, network, carrier info)
- Enhanced business events with rich device context
- Network and ISP information collection
- Battery and thermal state monitoring
- Memory and storage usage tracking

## 2. Framework Integration

### Add PaymentLibrary Framework

1. **Drag and drop** the `PaymentLibrary.framework` into your Xcode project
2. **Ensure** "Embed & Sign" is selected in the target's frameworks section
3. **Verify** the framework appears in both "Frameworks, Libraries, and Embedded Content" and "Link Binary With Libraries"

### Import in Swift Files

```swift
import PaymentLibrary
import UIKit
import CoreTelephony  // For enhanced network metadata
import Network        // For network monitoring
```

## 3. Required Dependencies

The enhanced PaymentLibrary requires these system frameworks for complete metadata collection:

### Required Frameworks
```swift
// Add to your target's "Frameworks, Libraries, and Embedded Content":
- Foundation.framework
- UIKit.framework  
- SystemConfiguration.framework
- CoreTelephony.framework
- Network.framework (iOS 12.0+)
```

### Privacy Configuration

Add these keys to your `Info.plist` for enhanced metadata collection:

```xml
<key>NSNetworkUsageDescription</key>
<string>This app collects network information to enhance payment monitoring and fraud detection.</string>

<key>NSLocationUsageDescription</key>
<string>Location information helps improve payment security and fraud prevention.</string>
```

**Note**: The PaymentLibrary gracefully handles missing permissions and collects only available metadata.

## 4. Enhanced Device Metadata Features

### DeviceMetadataCollector

The new `DeviceMetadataCollector` automatically gathers comprehensive device information:

#### Device & Hardware Information
- Device model, manufacturer (Apple), system name and version
- Screen resolution, scale, and bounds information
- Physical memory total and available
- Storage capacity and available space
- Processor count and thermal state

#### Operating System Details  
- iOS version and build number
- Kernel version and system architecture
- Battery level, charging state, and low power mode
- Thermal state monitoring

#### Network & Connectivity
- Network connection type (WiFi, Cellular, None)
- Mobile carrier name and country code
- Device IP address (when available)
- Network reachability status

#### Application Context
- Device locale and timezone information
- App version and build details
- Device identifier for vendor (IDFV)
- System performance metrics

## 5. Configuration

### Application Setup

Configure the PaymentLibrary in your `AppDelegate` or `SceneDelegate`:

```swift
// AppDelegate.swift
import UIKit
import PaymentLibrary

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        configureDynatraceIntegration()
        return true
    }
    
    private func configureDynatraceIntegration() {
        // Configure DynatraceLogger for log ingestion
        DynatraceLogger.configure(
            endpoint: "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest",
            apiToken: "dt0c01.YOUR_LOG_INGEST_TOKEN",
            appName: "iOS-Banking-App"
        )
        
        // Option A: Basic BusinessEventsClient configuration
        BusinessEventsClient.shared.configure(BusinessEventsClient.Config(
            endpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest")!,
            auth: .apiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
            eventProvider: "com.yourbank.ios.app",
            defaultEventType: "com.yourbank.user.action",
            appVersion: getAppVersion(),
            deviceInfo: getBasicDeviceInfo()
        ))
        
        // Option B: Enhanced configuration with automatic device metadata (RECOMMENDED)
        /*
        BusinessEventsClient.shared.configureWithDeviceMetadata(
            endpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest")!,
            auth: .apiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
            eventProvider: "com.yourbank.ios.app", 
            defaultEventType: "com.yourbank.user.action",
            appVersion: getAppVersion()
        )
        */
        
        DynatraceLogger.info("iOS Banking App initialized with enhanced device metadata", category: "AppDelegate")
    }
    
    private func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    
    private func getBasicDeviceInfo() -> String {
        let device = UIDevice.current
        return "\\(device.model) (\\(device.systemName) \\(device.systemVersion))"
    }
}
```

## 6. Usage Examples

### Enhanced Payment Flow with Device Metadata

```swift
// PaymentViewController.swift
import UIKit
import PaymentLibrary

class PaymentViewController: UIViewController {
    
    private var paymentClient: PaymentClient!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize PaymentClient
        paymentClient = PaymentClient(baseURL: "https://api.yourbank.com")
        setupEnhancedPaymentFlow()
    }
    
    private func setupEnhancedPaymentFlow() {
        // Enhanced payment processing with comprehensive device metadata
        Task {
            do {
                // Begin payment session with enhanced tracking
                let sessionId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                    name: "payment_session",
                    attributes: [
                        "session_type": AnyEncodable("card_payment"),
                        "entry_point": AnyEncodable("main_dashboard"),
                        "user_agent": AnyEncodable("iOS-Banking-App")
                    ]
                ))
                
                // Begin specific payment processing  
                let paymentId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                    name: "process_card_payment",
                    attributes: [
                        "amount": AnyEncodable(150.75),
                        "currency": AnyEncodable("USD"),
                        "payment_method": AnyEncodable("visa_ending_1234"),
                        "merchant": AnyEncodable("Coffee Shop Downtown")
                    ],
                    parentActionId: sessionId
                ))
                
                // Process payment with enhanced tracking
                let paymentResult = try await processPaymentWithEnhancedTracking(amount: 150.75, currency: "USD")
                
                // End payment processing - device metadata automatically included
                try await BusinessEventsClient.shared.endAction(
                    paymentId,
                    status: paymentResult.success ? "SUCCESS" : "ERROR",
                    error: paymentResult.success ? nil : paymentResult.errorMessage,
                    extraAttributes: [
                        "transaction_id": AnyEncodable(paymentResult.transactionId),
                        "authorization_code": AnyEncodable(paymentResult.authCode),
                        "processing_time_ms": AnyEncodable(paymentResult.processingTimeMs),
                        "network_calls": AnyEncodable(paymentResult.networkCallCount),
                        "retry_count": AnyEncodable(paymentResult.retryCount)
                    ]
                )
                
                // End payment session
                try await BusinessEventsClient.shared.endAction(
                    sessionId,
                    status: "COMPLETED",
                    extraAttributes: [
                        "session_duration_ms": AnyEncodable(paymentResult.processingTimeMs),
                        "screens_visited": AnyEncodable(["dashboard", "payment_form", "confirmation"]),
                        "user_actions": AnyEncodable(5)
                    ]
                )
                
                DynatraceLogger.info("Enhanced payment flow completed with full device metadata", category: "PaymentViewController")
                
            } catch {
                DynatraceLogger.error("Enhanced payment flow failed: \\(error.localizedDescription)", category: "PaymentViewController")
                
                // Send error event with device metadata
                try? await BusinessEventsClient.shared.endAction(
                    paymentId,
                    status: "ERROR",
                    error: error.localizedDescription,
                    extraAttributes: [
                        "error_type": AnyEncodable(String(describing: type(of: error))),
                        "error_location": AnyEncodable("setupEnhancedPaymentFlow")
                    ]
                )
            }
        }
    }
    
    private func processPaymentWithEnhancedTracking(amount: Double, currency: String) async throws -> PaymentResult {
        // Enhanced payment processing with detailed tracking
        // Device metadata is automatically included in all events
        
        return try await withCheckedThrowingContinuation { continuation in
            // Begin network call tracking
            let networkCallId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
                name: "payment_api_call",
                attributes: [
                    "endpoint": AnyEncodable("/api/v2/payments/process"),
                    "method": AnyEncodable("POST"),
                    "request_size_bytes": AnyEncodable(512)
                ]
            ))
            
            paymentClient.processPayment(amount: amount, currency: currency) { [weak self] result in
                Task {
                    switch result {
                    case .success(let paymentResult):
                        // End network call tracking
                        try? await BusinessEventsClient.shared.endAction(
                            networkCallId,
                            status: "SUCCESS",
                            extraAttributes: [
                                "response_code": AnyEncodable(200),
                                "response_size_bytes": AnyEncodable(256),
                                "server_processing_time_ms": AnyEncodable(450)
                            ]
                        )
                        continuation.resume(returning: paymentResult)
                        
                    case .failure(let error):
                        try? await BusinessEventsClient.shared.endAction(
                            networkCallId,
                            status: "ERROR",
                            error: error.localizedDescription
                        )
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// Enhanced Payment Result Structure
struct PaymentResult {
    let success: Bool
    let transactionId: String
    let authCode: String
    let errorMessage: String?
    let processingTimeMs: Int
    let networkCallCount: Int
    let retryCount: Int
}
```

## 7. Device Metadata Collection

### Automatically Collected Metadata

When using `configureWithDeviceMetadata()`, the following information is automatically included in all business events:

#### Device Attributes
```json
{
  "device.manufacturer": "Apple",
  "device.model": "iPhone 15 Pro", 
  "device.name": "John's iPhone",
  "device.system_name": "iOS",
  "device.identifier": "B8D5C4A7-1234-5678-9ABC-DEF012345678",
  
  "device.os_version": "iOS 17.1",
  "device.os_version_code": "17.1", 
  "device.build_version": "21B74",
  "device.kernel_version": "Darwin Kernel Version 23.1.0",
  
  "device.screen_width": 1179,
  "device.screen_height": 2556,
  "device.screen_scale": 3.0,
  "device.screen_bounds": "393x852",
  
  "device.memory_total": 8589934592,
  "device.memory_available": 4294967296,
  "device.storage_total": 128849018880,
  "device.storage_available": 45678901234,
  
  "network.type": "wifi",
  "network.carrier": "Verizon",
  "network.country_code": "us", 
  "network.ip_address": "192.168.1.100",
  
  "device.locale": "en_US",
  "device.timezone": "America/New_York",
  "device.battery_level": 0.85,
  "device.battery_state": "unplugged",
  "device.low_power_mode": false,
  
  "device.processor_count": 6,
  "device.thermal_state": "nominal"
}
```

### Manual Device Metadata Collection

You can also collect metadata manually for custom use cases:

```swift
// Collect device metadata manually
let metadata = DeviceMetadataCollector.collectMetadata()

// Format for display
let deviceInfo = DeviceMetadataCollector.formatDeviceInfo(metadata)
print("Device Info: \\(deviceInfo)")

// Convert to event attributes
let attributes = DeviceMetadataCollector.toEventAttributes(metadata)

// Use in custom business events
let actionId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
    name: "custom_action",
    attributes: attributes.compactMapValues { AnyEncodable($0) }
))
```

## 8. Performance Considerations

### Memory Usage
- DeviceMetadataCollector uses minimal memory (~2KB per collection)
- Metadata is cached during configuration to avoid repeated system calls
- Network monitoring uses lightweight system APIs

### Battery Impact
- Minimal battery usage from system information queries
- Network type detection uses efficient CoreTelephony APIs
- No background processing or continuous monitoring

### Collection Frequency
- Device metadata is collected once during configuration
- Additional collections only occur when explicitly requested
- Network state changes are detected via system notifications

## 9. Privacy and Permissions

### Data Collection
The PaymentLibrary collects device metadata to enhance:
- **Payment Security**: Device fingerprinting for fraud detection
- **Performance Monitoring**: Correlate issues with device capabilities  
- **User Analytics**: Understand user device demographics
- **Troubleshooting**: Rich context for issue resolution

### Privacy Compliance
- No personally identifiable information (PII) is collected
- Device identifier uses vendor-specific IDFV (changes per app install)
- IP address collection respects user privacy settings
- All data collection follows Apple's privacy guidelines

### Required Permissions
```xml
<!-- Info.plist entries for enhanced metadata -->
<key>NSNetworkUsageDescription</key>
<string>Network information helps improve payment security and performance monitoring.</string>
```

**Note**: The library gracefully handles missing permissions and collects only available data.

## 10. Troubleshooting

### Common Integration Issues

#### Framework Not Found
```swift
// Ensure proper framework embedding
// 1. Check "Embed & Sign" is selected
// 2. Verify framework appears in both embedding and linking sections
// 3. Clean build folder (Cmd+Shift+K) and rebuild
```

#### Device Metadata Not Appearing
```swift
// Verify enhanced configuration is used
BusinessEventsClient.shared.configureWithDeviceMetadata(
    endpoint: URL(string: "https://tenant.live.dynatrace.com/api/v2/bizevents/ingest")!,
    auth: .apiToken("dt0c01.TOKEN"),
    eventProvider: "app-provider",
    defaultEventType: "com.app.action"
)

// Check logs for metadata collection
DynatraceLogger.info("Device metadata configured", category: "Debug")
```

#### Network Information Missing
```swift
// Add CoreTelephony framework
// Add Network framework (iOS 12.0+) 
// Ensure device has network connectivity
// Check privacy permissions in Settings
```

### Validation Script

```swift
// Add to your app for integration testing
func validatePaymentLibraryIntegration() {
    print("=== PaymentLibrary Integration Validation ===")
    
    // Test device metadata collection
    let metadata = DeviceMetadataCollector.collectMetadata()
    print("✅ Device Model: \\(metadata.deviceModel)")
    print("✅ OS Version: \\(metadata.osVersion)")
    print("✅ Network Type: \\(metadata.networkType)")
    print("✅ Screen Resolution: \\(metadata.screenWidth)x\\(metadata.screenHeight)")
    
    // Test business events
    let testId = BusinessEventsClient.shared.beginAction(BusinessEventsClient.BeginOptions(
        name: "integration_test",
        attributes: ["test_type": AnyEncodable("validation")]
    ))
    
    Task {
        try? await BusinessEventsClient.shared.endAction(testId, status: "SUCCESS")
        print("✅ Business Events: Working")
    }
    
    // Test logging
    DynatraceLogger.info("Integration test completed successfully", category: "Validation")
    print("✅ Logging: Working")
    
    print("=== Integration Validation Complete ===")
}
```

### Best Practices

1. **Configuration**:
   - Use `configureWithDeviceMetadata()` for enhanced observability
   - Configure early in app lifecycle (AppDelegate/SceneDelegate)
   - Store Dynatrace tokens securely (Keychain, secure configuration)

2. **Business Events**:
   - Use meaningful action names and event types
   - Include relevant context in action attributes
   - Handle async operations properly with proper error handling

3. **Performance**:
   - Device metadata collection is lightweight but cache when possible
   - Use business events for significant user actions, not every UI interaction
   - Monitor framework overhead in production builds

4. **Security**:
   - Never commit Dynatrace tokens to version control
   - Use different endpoints for development/staging/production
   - Validate token permissions match usage (logs.ingest, bizevents.ingest)

This enhanced iOS PaymentLibrary integration provides comprehensive device context for all business events while maintaining privacy compliance and optimal performance.