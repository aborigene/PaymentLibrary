# iOS PaymentLibrary Real-Time Device Metadata Enhancement

## Overview

The iOS PaymentLibrary has been enhanced with three critical features for comprehensive device metadata tracking and session management:

1. **Session Started Business Event**: Automatic creation of a "session_started" event during singleton initialization
2. **Universal Device Metadata**: All business events automatically include comprehensive device metadata
3. **Real-Time Metadata Collection**: Fresh device metadata collected at the start and end of each action

## ✅ **Enhancements Implemented**

### 1. **Session Started Business Event**

#### **PaymentClient Enhancement**
```swift
// New session_started event in PaymentClient initialization
private init(baseUrl: String) {
    self.baseUrl = baseUrl
    
    // Configure services with enhanced device metadata collection
    configureBusinessEventsWithDeviceMetadata(...)
    
    // Create session_started business event with comprehensive device metadata
    Task {
        await createSessionStartedEvent()
    }
}

private func createSessionStartedEvent() async {
    // Collect fresh device metadata for session start
    let currentMetadata = DeviceMetadataCollector.collectMetadata()
    
    // Create comprehensive session_started event
    let sessionId = BusinessEventsClient.shared.beginAction(BeginOptions(
        name: "session_started",
        attributes: deviceAttributes + sessionAttributes
    ))
    
    // End immediately with success
    try await BusinessEventsClient.shared.endAction(sessionId, status: "SUCCESS")
}
```

#### **Session Started Event Attributes**
```json
{
  "action.name": "session_started",
  "action.status": "SUCCESS",
  "session.id": "uuid-generated-session-id",
  "session.start_time": "2025-10-23T10:30:00Z",
  "session.initialization_type": "singleton_created",
  "app.base_url": "https://api.bank.com",
  
  // Fresh device metadata (25+ attributes)
  "device.manufacturer": "Apple",
  "device.model": "iPhone 15 Pro",
  "device.os_version": "iOS 17.1",
  "device.battery_level": 0.87,
  "device.memory_available": 4234567890,
  "network.type": "wifi",
  "device.thermal_state": "nominal",
  // ... all other device attributes
  
  "session.components_initialized": [
    "BusinessEventsClient",
    "CrashReporterKit", 
    "DynatraceLogger",
    "DeviceMetadataCollector"
  ]
}
```

### 2. **Enhanced BusinessEventsClient - Real-Time Metadata**

#### **Fresh Metadata Collection on beginAction**
```swift
@discardableResult
public func beginAction(_ opts: BeginOptions) -> UUID {
    // ... existing logic
    
    // Collect fresh device metadata for this action
    var enhancedAttributes = opts.attributes
    if cfg.deviceMetadata != nil {
        // Collect real-time device metadata
        let currentMetadata = DeviceMetadataCollector.collectMetadata()
        let deviceAttributes = DeviceMetadataCollector.toEventAttributes(currentMetadata)
        
        // Add fresh device metadata to action attributes
        deviceAttributes.forEach { (key, value) in
            enhancedAttributes[key] = AnyEncodable(value)
        }
        
        // Add metadata collection timestamp
        enhancedAttributes["action.metadata_collection_time"] = AnyEncodable(ISO8601DateFormatter().string(from: now))
    }
    
    // Create action context with enhanced attributes
    let ctx = ActionContext(..., attributes: enhancedAttributes, ...)
}
```

#### **Fresh Metadata Collection on endAction**
```swift
public func endAction(_ actionId: UUID, ...) async throws {
    // ... existing logic
    
    // Add fresh device metadata at the end of the action
    if config?.deviceMetadata != nil {
        let currentMetadata = DeviceMetadataCollector.collectMetadata()
        let deviceAttributes = DeviceMetadataCollector.toEventAttributes(currentMetadata)
        
        // Add end-of-action metadata with prefix
        deviceAttributes.forEach { (key, value) in
            let endKey = "end.\(key)"
            data[endKey] = AnyEncodable(value)
        }
        
        // Add end metadata collection timestamp
        data["action.end_metadata_collection_time"] = AnyEncodable(ISO8601DateFormatter().string(from: finishedAt))
    }
}
```

### 3. **Complete Business Event Structure**

#### **Payment Transaction Example**
```json
{
  // Action Information
  "action.id": "uuid-action-id",
  "action.name": "process_payment",
  "action.status": "SUCCESS",
  "action.durationMs": 2340,
  
  // Business Data
  "payment.amount": 99.99,
  "payment.currency": "USD",
  "payment.method": "credit_card",
  "transaction.id": "txn_abc123",
  
  // Start-of-Action Device Metadata (fresh at action start)
  "device.manufacturer": "Apple",
  "device.model": "iPhone 15 Pro",
  "device.os_version": "iOS 17.1",
  "device.battery_level": 0.87,
  "device.memory_available": 4234567890,
  "network.type": "wifi",
  "device.thermal_state": "nominal",
  "action.metadata_collection_time": "2025-10-23T10:30:15Z",
  
  // End-of-Action Device Metadata (fresh at action end)
  "end.device.battery_level": 0.85,        // Battery decreased during action
  "end.device.memory_available": 4200000000, // Memory usage changed
  "end.network.type": "cellular",          // Network switched during action
  "end.device.thermal_state": "fair",     // Thermal state changed
  "action.end_metadata_collection_time": "2025-10-23T10:30:17Z"
}
```

## 🔄 **Real-Time Metadata Collection Benefits**

### **1. Dynamic State Tracking**
- **Battery Level Changes**: Track battery drain during payment processing
- **Memory Usage**: Monitor memory consumption patterns per action
- **Network Switching**: Detect network changes during transactions
- **Thermal State**: Monitor device performance under load

### **2. Enhanced Analytics**
- **Performance Correlation**: Link action duration with device state changes
- **Resource Usage**: Track resource consumption per payment operation
- **User Experience**: Correlate device performance with transaction success
- **Fraud Detection**: Detect suspicious device state patterns

### **3. Troubleshooting Capabilities**
- **State Comparison**: Before/after device state for each action
- **Resource Issues**: Identify actions causing memory or battery problems
- **Network Problems**: Track network-related payment failures
- **Performance Bottlenecks**: Correlate slow actions with device thermal state

## 📊 **Implementation Examples**

### **Usage in PaymentClient**
```swift
// Session started event created automatically
let client = PaymentClient.getInstance(baseUrl: "https://api.bank.com")

// All payment operations now include real-time device metadata
client.receivePayment(
    amount: 150.00,
    creditCardNumber: "4111111111111111",
    vendorName: "Coffee Shop",
    vendorId: "vendor123"
) { result in
    // Payment completed with:
    // - Fresh metadata at action start
    // - Fresh metadata at action end
    // - Complete device state tracking
}
```

### **Business Event Timeline**
```
1. App Launch:
   └── session_started event (fresh device metadata)

2. Payment Action Start:
   └── Collect fresh metadata (battery: 87%, memory: 4.2GB, network: wifi)

3. Payment Processing:
   └── [2.3 seconds of payment processing]

4. Payment Action End:
   └── Collect fresh metadata (battery: 85%, memory: 4.0GB, network: cellular)
   └── Send complete event with start + end metadata
```

## 🎯 **Key Features**

### **Session Management**
- ✅ **Automatic Session Tracking**: "session_started" event on initialization
- ✅ **Session Context**: Unique session ID and timestamps
- ✅ **Component Status**: Track initialized components and services

### **Real-Time Device Context**
- ✅ **Fresh Metadata**: Collected at action start and end
- ✅ **State Changes**: Track device state evolution during actions
- ✅ **Timestamp Tracking**: Precise timing of metadata collection

### **Enhanced Observability**
- ✅ **Complete Timeline**: Full device context from session start to action completion
- ✅ **Performance Insights**: Resource usage patterns and optimization opportunities
- ✅ **User Experience**: Device performance impact on payment success rates

## 🔧 **Configuration**

### **Automatic Enhancement**
```swift
// Enhanced metadata collection enabled by default
let client = PaymentClient.getInstance(baseUrl: baseUrl)
// ✅ session_started event created automatically
// ✅ All actions include real-time metadata
```

### **Custom Configuration**
```swift
let client = PaymentClient.getInstanceWithEnhancedMetadata(
    baseUrl: baseUrl,
    dynatraceEndpoint: customEndpoint,
    dynatraceToken: "dt0c01.TOKEN",
    eventProvider: "enhanced-banking-app"
)
// ✅ Custom Dynatrace configuration
// ✅ Full real-time metadata collection
```

## 📈 **Expected Outcomes**

### **Enhanced Analytics Dashboard**
- **Session Analysis**: Track user sessions from start to completion
- **Performance Metrics**: Device performance impact on payment success
- **Resource Monitoring**: Memory, battery, network usage per action
- **User Experience**: Correlation between device state and user satisfaction

### **Improved Fraud Detection**
- **Device Fingerprinting**: Unique device characteristics per session
- **Behavioral Analysis**: Unusual device state patterns
- **Session Validation**: Consistent device identity throughout sessions
- **Real-Time Risk Scoring**: Device performance-based risk assessment

### **Better Support & Debugging**
- **Complete Context**: Full device timeline for support tickets
- **Performance Troubleshooting**: Resource usage patterns and bottlenecks
- **Network Diagnostics**: Network state changes during failures
- **Proactive Monitoring**: Device performance alerts and notifications

This enhancement provides world-class device metadata tracking with real-time state monitoring, session management, and comprehensive observability for payment transactions while maintaining optimal performance and privacy compliance.