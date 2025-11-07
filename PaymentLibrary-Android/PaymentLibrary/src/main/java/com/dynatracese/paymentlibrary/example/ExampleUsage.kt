package com.dynatracese.paymentlibrary.example

import android.app.Application
import android.os.Build
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger

/**
 * Example Application class showing how to configure the PaymentLibrary with Dynatrace integration
 */
class ExampleApplication : Application() {
    

    
    override fun onCreate() {
        super.onCreate()
        
        // Configure DynatraceLogger for log ingestion
        configureDynatraceLogger()
        
        // Configure BusinessEventsClient for RUM monitoring
        configureBusinessEvents()
        
        // Log that the application started
        DynatraceLogger.info("PaymentLibrary Example Application started", "ExampleApplication")
    }
    
    private fun configureBusinessEvents() {
        val endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest"
        val apiToken = "dt0c01.YOUR_API_TOKEN_HERE" // Token with bizevents.ingest scope
        
        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = endpoint,
                auth = BusinessEventsClient.Auth.ApiToken(apiToken),
                eventProvider = "com.dynatracese.payment.android", // Matches iOS: com.unitedgames.payment.ios
                appVersion = getAppVersion(),
                deviceInfo = getDeviceInfo()
            )
        )
        
        DynatraceLogger.info("BusinessEventsClient configured successfully", "ExampleApplication")
    }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
    
    private fun configureDynatraceLogger() {
        val endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest"
        val apiToken = "dt0c01.YOUR_LOG_API_TOKEN_HERE" // Token with logs.ingest scope
        val appName = "PaymentLibrary-Android"
        
        DynatraceLogger.configure(endpoint, apiToken, appName)
    }
    
    private fun getDeviceInfo(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
    }
}

/**
 * Example usage of the PaymentLibrary in an Activity or Service
 */
class PaymentExampleUsage {

    
    suspend fun performPaymentWithBusinessEvents() {
        // Example of using BusinessEventsClient to track a payment flow
        // This creates the same parent/child action structure as the iOS version
        
        val parentActionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "Checkout",
                attributes = mapOf(
                    "checkout.type" to "credit_card",
                    "checkout.amount" to 99.99
                )
            )
        )
        
        try {
            // Child action - Add Card
            val addCardActionId = BusinessEventsClient.beginAction(
                BusinessEventsClient.BeginOptions(
                    name = "AddCard",
                    parentActionId = parentActionId,
                    attributes = mapOf(
                        "card.type" to "visa"
                    )
                )
            )
            
            // Simulate card processing
            DynatraceLogger.info("Processing credit card...", "PaymentExampleUsage")
            // ... card processing logic ...
            
            BusinessEventsClient.endAction(addCardActionId, status = "OK")
            
            // Another child action - Process Payment
            val processPaymentActionId = BusinessEventsClient.beginAction(
                BusinessEventsClient.BeginOptions(
                    name = "ProcessPayment",
                    parentActionId = parentActionId,
                    attributes = mapOf(
                        "payment.gateway" to "stripe"
                    )
                )
            )
            
            // Simulate payment processing
            DynatraceLogger.info("Processing payment...", "PaymentExampleUsage")
            // ... payment processing logic ...
            
            BusinessEventsClient.endAction(processPaymentActionId, status = "OK")
            
            // Complete parent action
            BusinessEventsClient.endAction(parentActionId, status = "OK")
            
            DynatraceLogger.info("Payment completed successfully", "PaymentExampleUsage")
            
        } catch (e: Exception) {
            // Report error in business events
            BusinessEventsClient.endAction(
                parentActionId, 
                status = "ERROR", 
                error = e.message ?: "Unknown error"
            )
            DynatraceLogger.error("Payment failed: ${e.message}", "PaymentExampleUsage", e)
            throw e
        }
    }
    
    suspend fun performPaymentWithAutoWrapping() {
        // Alternative approach using withAction for automatic handling
        BusinessEventsClient.withAction(
            name = "Quick Payment",
            attributes = mapOf(
                "payment.method" to "apple_pay",
                "amount" to 29.99
            )
        ) {
            DynatraceLogger.info("Processing quick payment...", "PaymentExampleUsage")
            // ... payment logic ...
            // If this block throws an exception, the action will automatically be marked as ERROR
            DynatraceLogger.info("Quick payment completed", "PaymentExampleUsage")
        }
    }
}