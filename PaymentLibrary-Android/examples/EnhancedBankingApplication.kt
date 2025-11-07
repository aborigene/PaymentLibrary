// Enhanced Banking Application with Device Metadata Collection
// This example shows how to use the new configureWithDeviceMetadata() method

import android.app.Application
import android.os.Build
import android.util.Log
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger

class EnhancedBankingApplication : Application() {
    
    override fun onCreate() {
        super.onCreate()
        
        Log.d("BankingApp", "Starting Enhanced Banking Application...")
        configureDynatraceIntegration()
        testDeviceMetadataCollection()
    }
    
    /**
     * Configure Dynatrace integration with enhanced device metadata collection
     */
    private fun configureDynatraceIntegration() {
        // Configure DynatraceLogger for log ingestion
        DynatraceLogger.configure(
            endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest",
            apiToken = "dt0c01.YOUR_LOG_INGEST_TOKEN", 
            appName = "Enhanced-Banking-Android"
        )
        
        // Configure BusinessEventsClient with automatic device metadata collection
        // This method automatically collects comprehensive device information
        BusinessEventsClient.configureWithDeviceMetadata(
            context = this,
            endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest",
            auth = BusinessEventsClient.Auth.ApiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"),
            eventProvider = "com.yourbank.enhanced.android",
            defaultEventType = "com.yourbank.enhanced.user.action",
            appVersion = getAppVersion()
        )
        
        DynatraceLogger.info("Enhanced Banking App initialized with comprehensive device metadata", "EnhancedBankingApplication")
    }
    
    /**
     * Test device metadata collection by sending a sample event
     */
    private fun testDeviceMetadataCollection() {
        try {
            // Create a sample business event to test metadata collection
            val testActionId = BusinessEventsClient.beginAction(
                name = "app_initialization",
                eventType = "com.yourbank.app.lifecycle",
                extraAttributes = mapOf(
                    "initialization_type" to "cold_start",
                    "app_version" to getAppVersion(),
                    "device_info" to "${Build.MANUFACTURER} ${Build.MODEL}"
                )
            )
            
            // Simulate some initialization work
            Thread.sleep(100)
            
            // End the action - this will automatically include all collected device metadata
            BusinessEventsClient.endAction(
                actionId = testActionId,
                status = "SUCCESS",
                extraAttributes = mapOf(
                    "initialization_duration_ms" to 100,
                    "features_enabled" to listOf("payment", "transfer", "balance_check")
                )
            )
            
            Log.d("BankingApp", "Device metadata test event sent successfully")
            
        } catch (e: Exception) {
            Log.e("BankingApp", "Failed to send device metadata test event: ${e.message}", e)
        }
    }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
}

/**
 * Enhanced Payment Activity demonstrating business events with device metadata
 */
class EnhancedPaymentActivity : AppCompatActivity() {
    
    private lateinit var paymentClient: PaymentClient
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize PaymentClient
        paymentClient = PaymentClient.getInstance(
            baseUrl = "https://api.yourbank.com",
            context = this
        )
        
        setupEnhancedPaymentFlow()
    }
    
    /**
     * Enhanced payment flow with comprehensive tracking
     */
    private fun setupEnhancedPaymentFlow() {
        lifecycleScope.launch {
            try {
                // Begin payment session with enhanced tracking
                val sessionId = BusinessEventsClient.beginAction(
                    name = "payment_session",
                    eventType = "com.yourbank.payment.session",
                    extraAttributes = mapOf(
                        "session_type" to "card_payment",
                        "entry_point" to "main_dashboard",
                        "user_agent" to "Banking-Android-App"
                    )
                )
                
                // Begin specific payment processing
                val paymentId = BusinessEventsClient.beginAction(
                    name = "process_card_payment", 
                    eventType = "com.yourbank.payment.transaction",
                    parentActionId = sessionId,
                    extraAttributes = mapOf(
                        "amount" to 150.75,
                        "currency" to "USD",
                        "payment_method" to "visa_ending_1234",
                        "merchant" to "Coffee Shop Downtown"
                    )
                )
                
                // Simulate payment processing
                delay(2000)
                val paymentResult = processPaymentWithEnhancedTracking(150.75, "USD")
                
                // End payment processing with success
                BusinessEventsClient.endAction(
                    actionId = paymentId,
                    status = if (paymentResult.success) "SUCCESS" else "ERROR",
                    error = if (!paymentResult.success) paymentResult.errorMessage else null,
                    extraAttributes = mapOf(
                        "transaction_id" to paymentResult.transactionId,
                        "authorization_code" to paymentResult.authCode,
                        "processing_time_ms" to paymentResult.processingTimeMs,
                        "network_calls" to paymentResult.networkCallCount,
                        "retry_count" to paymentResult.retryCount
                    )
                )
                
                // End payment session
                BusinessEventsClient.endAction(
                    actionId = sessionId,
                    status = "COMPLETED",
                    extraAttributes = mapOf(
                        "session_duration_ms" to (System.currentTimeMillis() - sessionStartTime),
                        "screens_visited" to listOf("dashboard", "payment_form", "confirmation"),
                        "user_actions" to 5
                    )
                )
                
                Log.d("PaymentActivity", "Enhanced payment flow completed with full device metadata")
                
            } catch (e: Exception) {
                Log.e("PaymentActivity", "Enhanced payment flow failed: ${e.message}", e)
                
                // Send error event with device metadata
                BusinessEventsClient.endAction(
                    actionId = paymentId,
                    status = "ERROR",
                    error = e.message ?: e.toString(),
                    extraAttributes = mapOf(
                        "error_type" to e.javaClass.simpleName,
                        "error_location" to "setupEnhancedPaymentFlow"
                    )
                )
            }
        }
    }
    
    private suspend fun processPaymentWithEnhancedTracking(
        amount: Double,
        currency: String
    ): PaymentResult {
        // Enhanced payment processing with detailed tracking
        // Device metadata is automatically included in all events
        
        return try {
            // Begin network call tracking
            val networkCallId = BusinessEventsClient.beginAction(
                name = "payment_api_call",
                eventType = "com.yourbank.api.request",
                extraAttributes = mapOf(
                    "endpoint" to "/api/v2/payments/process",
                    "method" to "POST",
                    "request_size_bytes" to 512
                )
            )
            
            val result = paymentClient.processPayment(amount, currency)
            
            // End network call tracking
            BusinessEventsClient.endAction(
                actionId = networkCallId,
                status = "SUCCESS",
                extraAttributes = mapOf(
                    "response_code" to 200,
                    "response_size_bytes" to 256,
                    "server_processing_time_ms" to 450
                )
            )
            
            result
            
        } catch (e: Exception) {
            Log.e("PaymentActivity", "Payment processing failed: ${e.message}", e)
            throw e
        }
    }
}

/**
 * Data class for enhanced payment results
 */
data class PaymentResult(
    val success: Boolean,
    val transactionId: String,
    val authCode: String,
    val errorMessage: String? = null,
    val processingTimeMs: Long,
    val networkCallCount: Int,
    val retryCount: Int = 0
)