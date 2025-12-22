# PaymentLibrary - iOS

A Swift framework for payment processing with built-in Dynatrace observability and comprehensive device metadata collection.

## Overview

This library enables iOS applications to use payment functions while providing comprehensive telemetry data to Dynatrace, independently of whatever agent the main application is using.

**Key Features:**
- Payment processing with real-time monitoring
- Business events tracking with CloudEvents format
- Comprehensive device metadata collection (25+ attributes)
- Direct log ingestion to Dynatrace
- Crash reporting with stack trace symbolication
- Automatic session management

## Framework Structure

```
PaymentLibrary.framework/
├── PaymentClient           - Main payment processing interface
├── BusinessEventsClient    - Dynatrace business events integration
├── DynatraceLogger        - Direct log ingestion
├── DeviceMetadataCollector - Automatic device metadata collection
├── PaymentCrashHandler    - Crash reporting
└── SwiftyBeaverDynatraceLogger - Logging destination
```

## Installation

### Option 1: Framework Integration (Recommended)

1. **Build the framework:**
   ```bash
   cd PaymentLibrary-iOS
   ./build.sh
   ```
   This generates `PaymentLibrary.framework` in the `output/` directory.

2. **Add to your Xcode project:**
   - Drag and drop `PaymentLibrary.framework` into your Xcode project
   - Select **"Embed & Sign"** in the target's "Frameworks, Libraries, and Embedded Content"
   - Verify it appears in both the General tab and "Link Binary With Libraries"

3. **Import in your Swift files:**
   ```swift
   import PaymentLibrary
   ```

### Option 2: Source Integration

Add the PaymentLibrary source files directly to your project (useful for development).

## Quick Start

### 1. Initialize in AppDelegate

```swift
import UIKit
import PaymentLibrary

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize PaymentClient with enhanced device metadata
        PaymentClient.getInstanceWithEnhancedMetadata(
            baseUrl: "https://api.yourbank.com",
            dynatraceEndpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest"),
            dynatraceToken: "dt0c01.YOUR_BIZEVENTS_TOKEN",
            eventProvider: "com.yourbank.ios.app"
        )
        
        return true
    }
}
```

### 2. Process Payments

```swift
import PaymentLibrary

class PaymentViewController: UIViewController {
    
    func processPayment() {
        let client = PaymentClient.shared
        
        client.receivePayment(
            amount: 150.75,
            creditCardNumber: "4532123456789012",
            vendorName: "Coffee Shop",
            vendorId: "vendor_123"
        ) { [weak self] result in
            switch result {
            case .success(let transactionId):
                print("✅ Payment successful: \(transactionId)")
                // Update UI with success
                
            case .failure(let error):
                print("❌ Payment failed: \(error.localizedDescription)")
                // Show error to user
            }
        }
    }
}
```

## Configuration Options

### Basic Initialization (Legacy)

```swift
// Simple initialization without enhanced metadata
let client = PaymentClient.getInstance(baseUrl: "https://api.yourbank.com")
```

### Enhanced Initialization (Recommended)

```swift
// Automatic device metadata collection and Dynatrace integration
PaymentClient.getInstanceWithEnhancedMetadata(
    baseUrl: "https://api.yourbank.com",
    dynatraceEndpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest"),
    dynatraceToken: "dt0c01.YOUR_BIZEVENTS_TOKEN",
    eventProvider: "com.yourbank.ios.app"
)
```

**Note:** The enhanced initialization automatically:
- Collects comprehensive device metadata (OS, network, hardware info)
- Configures Dynatrace business events tracking
- Sets up crash reporting with proper symbolication
- Creates a `session_started` business event

### Log Level Configuration

Control logging verbosity with configurable log levels:

**Available Log Levels:**
- `.verbose` - All logs including very detailed debug information
- `.debug` - Debug information and above
- `.info` - Informational messages and above (default, recommended for production)
- `.warn` - Warnings and errors only
- `.error` - Error messages only
- `.none` - No logging

**Usage:**
```swift
BusinessEventsClient.shared.configure(BusinessEventsClient.Config(
    endpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest")!,
    auth: .apiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
    eventProvider: "com.yourbank.ios.app",
    defaultEventType: "com.yourbank.user.action",
    logLevel: .info  // Set desired log level (default: .info)
))
```

**Best Practices:**
- **Production**: Use `.info` or `.warn` for cleaner logs
- **Development**: Use `.debug` or `.verbose` for troubleshooting
- **Testing**: Use `.info` to verify key operations without noise

The log level affects all internal logging from BusinessEventsClient, including:
- Action start/end notifications
- Timeout handling
- Event serialization
- Device metadata collection
- Stack trace filtering

### Manual Configuration

```swift
// Configure business events manually
let client = PaymentClient.shared
client.configureBusinessEventsWithDeviceMetadata(
    endpoint: URL(string: "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest")!,
    auth: .apiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
    eventProvider: "com.yourbank.ios.app"
)
```

## Automatic Version Tracking

### Library Version Collection

The PaymentLibrary **automatically collects its own version** from the framework's `Info.plist`:
- `CFBundleShortVersionString` → Used as `appVersion` in telemetry
- `CFBundleVersion` → Used as build number in crash reports
- Framework UUID → Used for stack trace symbolication

**Important:** The library version is collected internally and cannot be overridden. This ensures:
- ✅ Correct stack trace deobfuscation in Dynatrace
- ✅ Accurate correlation between crashes and library versions
- ✅ No version mismatch between app and library telemetry

### What Gets Sent to Dynatrace

```json
{
  "action.name": "payment_process",
  "app.version": "1.0.0",           // Library version (automatic)
  "crash.version": "1.0.0",         // Library version in crash reports
  "crash.build": "42",              // Library build number
  "crash.uuid": "A1B2C3D4-...",    // Framework UUID for symbolication
  "device.info": "iPhone 14 (iOS 17.1)",
  "crash.bundleId": "com.dynatracese.PaymentLibrary"
}
```

### Symbolication Requirements

For proper crash symbolication in Dynatrace:
1. `./build.sh` script will build the library and generate the dSYM .zip files
2. These .zip files must be processed using the scripts on helperScripts folder. These scripts can be added to the pipeline for automatic generation of the symbol files and must be run on Mac machine
3. **Upload dSYM JSON generated files** for each PaymentLibrary version
4. **Verify UUID match** between dSYM and framework 
   ```bash
   dwarfdump --uuid PaymentLibrary.framework/PaymentLibrary
   ```
5. **Build number tracking** ensures correct symbol file mapping

The files must be uploaded to a custom app in Dynatrace that will handled deofuscation

## Dynatrace Integration

### Business Events Tracking

Every payment operation is automatically tracked as a business event:

```swift
// Events sent automatically:
// 1. session_started (on library initialization)
// 2. payment_started (when receivePayment is called)
// 3. payment_completed/payment_failed (on success/failure)
```

### Custom Business Events

Track custom user actions:

```swift
// Begin an action
let actionId = BusinessEventsClient.shared.beginAction(
    BusinessEventsClient.BeginOptions(
        name: "checkout_flow",
        attributes: [
            "cart_value": AnyEncodable(299.99),
            "items_count": AnyEncodable(3)
        ]
    )
)

// End the action
Task {
    try await BusinessEventsClient.shared.endAction(
        actionId,
        status: "SUCCESS",
        extraAttributes: [
            "duration_ms": AnyEncodable(1250),
            "steps_completed": AnyEncodable(4)
        ]
    )
}
```

### Logging to Dynatrace

```swift
// Configure logger (done automatically with getInstanceWithEnhancedMetadata)
DynatraceLogger.configure(
    endpoint: "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest",
    apiToken: "dt0c01.YOUR_LOG_INGEST_TOKEN",
    appName: "iOS-Banking-App"
)

// Use logging methods
DynatraceLogger.info("Payment initiated", category: "PaymentFlow")
DynatraceLogger.warning("Retry attempt", category: "Network")
DynatraceLogger.error("Payment failed", category: "PaymentFlow")
```

## Device Metadata Collection

The library automatically collects 25+ device attributes:

### Hardware & System
- Device model, manufacturer, system version
- Screen resolution, scale, memory
- Storage capacity, processor count
- Battery level, thermal state

### Network & Connectivity
- Network type (WiFi, Cellular, None)
- Carrier name and country code
- IP address, reachability status

### Application Context
- Locale, timezone, app version
- Device identifier (IDFV)
- Build number and architecture

**Privacy:** All metadata collection respects iOS privacy settings and handles missing permissions gracefully.

## Error Handling

```swift
client.receivePayment(
    amount: amount,
    creditCardNumber: cardNumber,
    vendorName: vendor,
    vendorId: vendorId
) { result in
    switch result {
    case .success(let transactionId):
        // Handle success
        DynatraceLogger.info("Payment successful: \(transactionId)", category: "Payment")
        
    case .failure(let error):
        // Handle failure - automatically tracked in Dynatrace
        DynatraceLogger.error("Payment error: \(error.localizedDescription)", category: "Payment")
        
        if let paymentError = error as? PaymentError {
            switch paymentError {
            case .invalidCard:
                // Show invalid card message
            case .networkError:
                // Show network error message
            case .serverError:
                // Show server error message
            }
        }
    }
}
```

## Crash Reporting

Crash reporting is automatically configured when using `getInstanceWithEnhancedMetadata()`:

```swift
// Crashes are automatically captured and sent to Dynatrace with:
// - Stack trace with proper symbolication
// - Device metadata at crash time
// - Library version and UUID
// - Current action context (if any)
// - Loaded images list (filtered by stack trace)
```

## Testing

For testing purposes, use the `"TEST_ONLY"` base URL to simulate payments without backend calls:

```swift
let testClient = PaymentClient.getInstance(baseUrl: "TEST_ONLY")

testClient.receivePayment(
    amount: 100.0,
    creditCardNumber: "4532123456789012",
    vendorName: "Test Merchant",
    vendorId: "test_vendor"
) { result in
    // Always succeeds in TEST_ONLY mode with mock transaction ID
    print("Test payment result: \(result)")
}
```

## Best Practices

1. **Initialize Early**: Configure PaymentClient in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`

2. **Use Enhanced Initialization**: Always use `getInstanceWithEnhancedMetadata()` for production to get comprehensive telemetry

3. **Don't Override Version**: Let the library collect its own version automatically for proper symbolication

4. **Test with TEST_ONLY**: Use test mode during development to avoid real payment processing

5. **Handle All Errors**: Always implement both success and failure callbacks

6. **Monitor Dynatrace**: Check business events and logs in Dynatrace to verify integration

7. **Upload dSYMs**: Ensure dSYM files are uploaded to Dynatrace for each library version

## Required Dependencies

The PaymentLibrary uses these system frameworks:
- `Foundation.framework`
- `UIKit.framework`
- `SystemConfiguration.framework`
- `CoreTelephony.framework`
- `Network.framework` (iOS 12.0+)

No external dependencies required - everything is included in the framework.

## Troubleshooting

### Framework Not Found
- Ensure "Embed & Sign" is selected in target settings
- Clean build folder (Cmd+Shift+K) and rebuild

### Crashes Not Appearing in Dynatrace
- Verify dSYM files are uploaded for the library version
- Check that crash.uuid matches the framework UUID
- Ensure proper API token permissions (bizevents.ingest)

### Business Events Not Showing
- Verify API token has `bizevents.ingest` scope
- Check network connectivity
- Look for error logs in Xcode console

### Device Metadata Missing
- Check Info.plist for required privacy descriptions
- Verify framework has access to system APIs
- Some metadata requires specific permissions (location, network)

## Support & Documentation

For detailed integration examples and advanced usage, see:
- [BANKING_APP_INTEGRATION_GUIDE.md](BANKING_APP_INTEGRATION_GUIDE.md) - Complete integration guide
- [DEVICE_METADATA_ENHANCEMENT_SUMMARY.md](DEVICE_METADATA_ENHANCEMENT_SUMMARY.md) - Device metadata details
- Example code in `examples/` directory

## Version History

### Version 1.0.0
- Initial release with payment processing
- Dynatrace business events integration
- Comprehensive device metadata collection (25+ attributes)
- Automatic crash reporting
- SwiftyBeaver logging integration
- CloudEvents format support
- Automatic version and UUID collection for symbolication
