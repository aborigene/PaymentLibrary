# PaymentLibrary for Android - Dynatrace Integration

This Android library provides payment processing capabilities with integrated Dynatrace monitoring using Business Events and direct log ingestion.

## Overview

The PaymentLibrary-Android has been updated to match the functionality of the iOS version with the following key features:

1. **Business Events Client**: RUM monitoring using Dynatrace Business Events API
2. **Dynatrace Log Appender**: Direct log streaming to Dynatrace Log Ingest API using Log4j2
3. **OpenKit Removed**: All OpenKit dependencies have been removed in favor of direct API integration

## Key Features

### Business Events Client

The `BusinessEventsClient` provides the same functionality as the iOS version:

- **Parent/Child Action Tracking**: Support for hierarchical action tracking with W3C traceparent
- **CloudEvents Format**: Sends data in CloudEvents format to `/api/v2/bizevents/ingest`
- **Automatic Error Handling**: Actions are automatically marked with error status on exceptions
- **Correlation**: Maintains trace context across parent and child actions

### DynatraceLogger

The `DynatraceLogger` is a custom Android logger that:

- **Direct Integration**: Sends logs directly to Dynatrace Log Ingest API
- **Retry Logic**: Implements exponential backoff for failed requests
- **Android Compatible**: Works with Android's minimum SDK requirements
- **Rich Context**: Includes thread, logger name, and timestamp information
- **Dual Logging**: Logs both to Android LogCat and Dynatrace simultaneously

## Configuration

### 1. Dependencies

The library now includes the following dependencies:

```kotlin
// HTTP client and JSON serialization
implementation("com.squareup.okhttp3:okhttp:4.12.0")
implementation("com.google.code.gson:gson:2.10.1")
implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

// Coroutines for async operations
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
```

### 2. Business Events Configuration

Configure the BusinessEventsClient in your Application class:

```kotlin
BusinessEventsClient.configure(
    BusinessEventsClient.Config(
        endpoint = "https://your-tenant.live.dynatrace.com/api/v2/bizevents/ingest",
        auth = BusinessEventsClient.Auth.ApiToken("dt0c01.YOUR_API_TOKEN"),
        eventProvider = "com.yourcompany.payment.android",
        defaultEventType = "com.yourcompany.user.action",
        appVersion = "1.0.0",
        deviceInfo = "Samsung Galaxy S21 (Android 11)"
    )
)
```

### 3. Log4j2 Configuration

Create a `log4j2.xml` file in `src/main/resources/`:

```xml
### DynatraceLogger Configuration

Configure the DynatraceLogger in your Application class:

```kotlin
DynatraceLogger.configure(
    endpoint = "https://your-tenant.live.dynatrace.com/api/v2/logs/ingest",
    apiToken = "dt0c01.YOUR_LOG_API_TOKEN",
    appName = "PaymentLibrary-Android"
)
```
```

## Usage Examples

### Basic Business Events Tracking

```kotlin
// Simple action tracking with automatic error handling
BusinessEventsClient.withAction(
    name = "Payment Processing",
    attributes = mapOf(
        "amount" to 99.99,
        "currency" to "USD"
    )
) {
    // Your payment logic here
    // If an exception is thrown, the action is automatically marked as ERROR
    processPayment()
}
```

### Parent/Child Action Hierarchy

```kotlin
// Start parent action
val checkoutActionId = BusinessEventsClient.beginAction(
    BusinessEventsClient.BeginOptions(
        name = "Checkout",
        attributes = mapOf("total" to 199.98)
    )
)

// Start child action
val cardValidationActionId = BusinessEventsClient.beginAction(
    BusinessEventsClient.BeginOptions(
        name = "CardValidation",
        parentActionId = checkoutActionId,
        attributes = mapOf("cardType" to "visa")
    )
)

try {
    // Validate card
    validateCard()
    BusinessEventsClient.endAction(cardValidationActionId, status = "OK")
    
    // Process payment
    processPayment()
    BusinessEventsClient.endAction(checkoutActionId, status = "OK")
    
} catch (e: Exception) {
    BusinessEventsClient.endAction(
        cardValidationActionId,
        status = "ERROR", 
        error = e.message
    )
    BusinessEventsClient.endAction(
        checkoutActionId,
        status = "ERROR", 
        error = e.message
    )
}
```

### Logging Integration

```kotlin
class PaymentProcessor {
    
    fun processPayment(amount: Double) {
        DynatraceLogger.info("Starting payment processing for amount: $amount", "PaymentProcessor")
        
        try {
            // Payment logic
            DynatraceLogger.debug("Validating payment details", "PaymentProcessor")
            // ...
            DynatraceLogger.info("Payment processed successfully", "PaymentProcessor")
            
        } catch (e: Exception) {
            DynatraceLogger.error("Payment processing failed: ${e.message}", "PaymentProcessor", e)
            throw e
        }
    }
}
```

## API Requirements

### Business Events API

- **Endpoint**: `https://{tenant}.live.dynatrace.com/api/v2/bizevents/ingest`
- **Token Scope**: `bizevents.ingest`
- **Content-Type**: `application/cloudevent+json`

### Log Ingest API

- **Endpoint**: `https://{tenant}.live.dynatrace.com/api/v2/logs/ingest`
- **Token Scope**: `logs.ingest`
- **Content-Type**: `application/json; charset=utf-8`

## Migration from OpenKit

The following changes were made during migration:

1. **Removed Dependencies**:
   - `com.dynatrace.openkit:openkit-java:3.3.0`

2. **Replaced Functionality**:
   - OpenKit sessions → BusinessEventsClient actions
   - OpenKit crash reporting → DynatraceLogger error logging
   - OpenKit RUM → Business Events API

3. **Enhanced Features**:
   - W3C traceparent support for better correlation
   - CloudEvents format for standardization
   - Direct API integration for better control
   - Retry logic with exponential backoff
   - Android-native logging solution

## Error Handling

The library implements robust error handling:

- **BusinessEventsClient**: Automatic retry for 5xx errors and network failures
- **DynatraceLogger**: Exponential backoff with configurable retry attempts
- **Graceful Degradation**: Logging failures don't affect application functionality
- **Dual Logging**: Always logs to Android LogCat even if Dynatrace logging fails

## Performance Considerations

- All network operations are asynchronous using Kotlin coroutines
- Business events are sent immediately when actions complete
- Log events are sent asynchronously without blocking the main thread
- Failed requests are retried with exponential backoff to prevent overwhelming the API

## Troubleshooting

1. **Business Events not appearing**: Check API token has `bizevents.ingest` scope
2. **Logs not appearing**: Check API token has `logs.ingest` scope and DynatraceLogger is properly configured
3. **Network errors**: Verify endpoint URLs and network connectivity
4. **Configuration errors**: Check DynatraceLogger.configure() is called before using logging methods
5. **Local logs working but remote not**: Check Android LogCat - DynatraceLogger will show error messages there