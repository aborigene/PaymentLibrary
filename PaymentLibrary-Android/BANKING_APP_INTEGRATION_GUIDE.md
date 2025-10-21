# Banking App Integration Guide - PaymentLibrary with Dynatrace

This guide shows how to integrate the PaymentLibrary (with Dynatrace BusinessEvents and DynatraceLogger) into your main Banking Android application using the generated AAR file.

## 1. Generate and Import PaymentLibrary AAR

### Step 1: Generate the AAR file

First, build the PaymentLibrary to generate the AAR file:

```bash
cd PaymentLibrary-Android
./gradlew :PaymentLibrary:assembleRelease
```

This will generate the AAR file at:
```
PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar
```

### Step 2: Copy AAR to Banking App

Copy the generated AAR file to your Banking App's `libs` directory:

```bash
# From PaymentLibrary-Android directory
cp PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar /path/to/your/BankingApp/app/libs/
```

### Step 3: Configure Banking App Dependencies

In your Banking app's `build.gradle.kts` (app module):

```kotlin
android {
    // ... existing configuration
}

dependencies {
    // Import the PaymentLibrary AAR
    implementation(files("libs/paymentlibrary-release.aar"))
    
    // Add required dependencies that PaymentLibrary needs
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
    
    // ... your other dependencies
}
```

**Note**: Make sure your Banking App's `libs` directory exists. If it doesn't, create it:
```bash
mkdir -p /path/to/your/BankingApp/app/libs
```

## 2. Application Class Setup

Create or update your Application class to configure the Dynatrace integration:

```kotlin
// BankingApplication.kt
import android.app.Application
import android.os.Build
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger

class BankingApplication : Application() {
    
    override fun onCreate() {
        super.onCreate()
        
        // Configure Dynatrace integrations
        configureDynatraceIntegration()
    }
    
    private fun configureDynatraceIntegration() {
        // 1. Configure DynatraceLogger for log ingestion
        DynatraceLogger.configure(
            endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/logs/ingest",
            apiToken = "dt0c01.YOUR_LOG_INGEST_TOKEN", // Token with logs.ingest scope
            appName = "Banking-Android-App"
        )
        
        // 2. Configure BusinessEventsClient for RUM monitoring
        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = "https://YOUR_TENANT.live.dynatrace.com/api/v2/bizevents/ingest",
                auth = BusinessEventsClient.Auth.ApiToken("dt0c01.YOUR_BIZEVENTS_TOKEN"), // Token with bizevents.ingest scope
                eventProvider = "com.yourbank.banking.android",
                defaultEventType = "com.yourbank.user.action",
                appVersion = getAppVersion(),
                deviceInfo = getDeviceInfo()
            )
        )
        
        DynatraceLogger.info("Banking App initialized with Dynatrace integration", "BankingApplication")
    }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
    
    private fun getDeviceInfo(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
    }
}
```

### Register Application Class in Manifest

```xml
<!-- AndroidManifest.xml -->
<application
    android:name=".BankingApplication"
    android:allowBackup="true"
    android:icon="@mipmap/ic_launcher"
    android:label="@string/app_name"
    android:theme="@style/AppTheme">
    
    <!-- Your activities -->
    
</application>
```

## 3. Payment Integration in Activities/ViewModels

### Example: Payment Activity

```kotlin
// PaymentActivity.kt
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.dynatracese.paymentlibrary.PaymentClient
import com.dynatracese.paymentlibrary.PaymentCallback
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger
import kotlinx.coroutines.launch

class PaymentActivity : AppCompatActivity() {
    
    private lateinit var paymentClient: PaymentClient
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_payment)
        
        // Initialize PaymentClient
        paymentClient = PaymentClient.getInstance(
            baseUrl = "https://api.yourbank.com",
            context = this
        )
        
        setupPaymentButton()
    }
    
    private fun setupPaymentButton() {
        findViewById<Button>(R.id.payButton).setOnClickListener {
            performPayment()
        }
    }
    
    private fun performPayment() {
        lifecycleScope.launch {
            // Track the entire payment flow with BusinessEvents
            BusinessEventsClient.withAction(
                name = "Banking Payment Flow",
                attributes = mapOf(
                    "payment.type" to "credit_card",
                    "payment.amount" to 150.00,
                    "user.id" to getCurrentUserId()
                )
            ) {
                try {
                    DynatraceLogger.info("Starting payment process", "PaymentActivity")
                    
                    // Call PaymentLibrary
                    paymentClient.receivePayment(
                        amount = 150.00,
                        creditCardNumber = "4111111111111111",
                        vendorName = "YourBank Store",
                        vendorId = "BANK001",
                        callback = object : PaymentCallback {
                            override fun onPaymentSuccess(transactionId: String) {
                                handlePaymentSuccess(transactionId)
                            }
                            
                            override fun onPaymentFailure(error: String) {
                                handlePaymentFailure(error)
                            }
                        },
                        crashStatus = false // Set to true for testing crash scenarios
                    )
                } catch (e: Exception) {
                    DynatraceLogger.error("Payment process failed", "PaymentActivity", e)
                    throw e // Re-throw so BusinessEventsClient marks action as ERROR
                }
            }
        }
    }
    
    private fun handlePaymentSuccess(transactionId: String) {
        DynatraceLogger.info("Payment successful - Transaction ID: $transactionId", "PaymentActivity")
        
        // Track successful payment as separate business event
        lifecycleScope.launch {
            BusinessEventsClient.withAction(
                name = "Payment Success",
                attributes = mapOf(
                    "transaction.id" to transactionId,
                    "payment.status" to "completed"
                )
            ) {
                // Update UI
                runOnUiThread {
                    showSuccessMessage("Payment successful! Transaction ID: $transactionId")
                }
            }
        }
    }
    
    private fun handlePaymentFailure(error: String) {
        DynatraceLogger.error("Payment failed: $error", "PaymentActivity")
        
        // Track failed payment as separate business event
        lifecycleScope.launch {
            BusinessEventsClient.withAction(
                name = "Payment Failure",
                attributes = mapOf(
                    "payment.error" to error,
                    "payment.status" to "failed"
                )
            ) {
                // Update UI
                runOnUiThread {
                    showErrorMessage("Payment failed: $error")
                }
            }
        }
    }
    
    private fun getCurrentUserId(): String {
        // Get current user ID from your authentication system
        return "user_123456"
    }
    
    private fun showSuccessMessage(message: String) {
        // Show success UI
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }
    
    private fun showErrorMessage(message: String) {
        // Show error UI
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }
}
```

### Example: ViewModel Integration (MVVM Architecture)

```kotlin
// PaymentViewModel.kt
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dynatracese.paymentlibrary.PaymentClient
import com.dynatracese.paymentlibrary.PaymentCallback
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class PaymentViewModel(
    private val paymentClient: PaymentClient
) : ViewModel() {
    
    private val _paymentState = MutableStateFlow<PaymentState>(PaymentState.Idle)
    val paymentState: StateFlow<PaymentState> = _paymentState
    
    fun processPayment(paymentRequest: PaymentRequest) {
        viewModelScope.launch {
            _paymentState.value = PaymentState.Loading
            
            // Track payment with hierarchical actions
            val paymentFlowActionId = BusinessEventsClient.beginAction(
                BusinessEventsClient.BeginOptions(
                    name = "Payment Flow",
                    attributes = mapOf(
                        "amount" to paymentRequest.amount,
                        "currency" to paymentRequest.currency,
                        "merchant" to paymentRequest.merchantId
                    )
                )
            )
            
            try {
                // Child action: Validation
                val validationActionId = BusinessEventsClient.beginAction(
                    BusinessEventsClient.BeginOptions(
                        name = "Payment Validation",
                        parentActionId = paymentFlowActionId,
                        attributes = mapOf("validation.type" to "card_details")
                    )
                )
                
                DynatraceLogger.info("Validating payment details", "PaymentViewModel")
                // Validation logic here...
                BusinessEventsClient.endAction(validationActionId, status = "OK")
                
                // Child action: Processing
                val processingActionId = BusinessEventsClient.beginAction(
                    BusinessEventsClient.BeginOptions(
                        name = "Payment Processing",
                        parentActionId = paymentFlowActionId,
                        attributes = mapOf("processor" to "PaymentLibrary")
                    )
                )
                
                paymentClient.receivePayment(
                    amount = paymentRequest.amount,
                    creditCardNumber = paymentRequest.cardNumber,
                    vendorName = paymentRequest.merchantName,
                    vendorId = paymentRequest.merchantId,
                    callback = object : PaymentCallback {
                        override fun onPaymentSuccess(transactionId: String) {
                            viewModelScope.launch {
                                BusinessEventsClient.endAction(processingActionId, status = "OK")
                                BusinessEventsClient.endAction(paymentFlowActionId, status = "OK")
                                
                                _paymentState.value = PaymentState.Success(transactionId)
                                DynatraceLogger.info("Payment completed successfully", "PaymentViewModel")
                            }
                        }
                        
                        override fun onPaymentFailure(error: String) {
                            viewModelScope.launch {
                                BusinessEventsClient.endAction(processingActionId, status = "ERROR", error = error)
                                BusinessEventsClient.endAction(paymentFlowActionId, status = "ERROR", error = error)
                                
                                _paymentState.value = PaymentState.Error(error)
                                DynatraceLogger.error("Payment processing failed: $error", "PaymentViewModel")
                            }
                        }
                    },
                    crashStatus = false
                )
                
            } catch (e: Exception) {
                BusinessEventsClient.endAction(paymentFlowActionId, status = "ERROR", error = e.message)
                _paymentState.value = PaymentState.Error(e.message ?: "Unknown error")
                DynatraceLogger.error("Payment flow error", "PaymentViewModel", e)
            }
        }
    }
}

sealed class PaymentState {
    object Idle : PaymentState()
    object Loading : PaymentState()
    data class Success(val transactionId: String) : PaymentState()
    data class Error(val message: String) : PaymentState()
}

data class PaymentRequest(
    val amount: Double,
    val currency: String,
    val cardNumber: String,
    val merchantName: String,
    val merchantId: String
)
```

## 4. Dependency Injection (if using Dagger/Hilt)

```kotlin
// PaymentModule.kt
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ActivityComponent
import dagger.hilt.android.qualifiers.ApplicationContext
import com.dynatracese.paymentlibrary.PaymentClient

@Module
@InstallIn(ActivityComponent::class)
object PaymentModule {
    
    @Provides
    fun providePaymentClient(@ApplicationContext context: Context): PaymentClient {
        return PaymentClient.getInstance(
            baseUrl = "https://api.yourbank.com",
            context = context
        )
    }
}
```

## 5. Configuration Management

### Using BuildConfig for Different Environments

```kotlin
// In build.gradle.kts (app module)
android {
    buildTypes {
        debug {
            buildConfigField("String", "DYNATRACE_TENANT", "\"https://dev-tenant.live.dynatrace.com\"")
            buildConfigField("String", "DYNATRACE_BIZEVENTS_TOKEN", "\"dt0c01.DEV_BIZEVENTS_TOKEN\"")
            buildConfigField("String", "DYNATRACE_LOGS_TOKEN", "\"dt0c01.DEV_LOGS_TOKEN\"")
        }
        release {
            buildConfigField("String", "DYNATRACE_TENANT", "\"https://prod-tenant.live.dynatrace.com\"")
            buildConfigField("String", "DYNATRACE_BIZEVENTS_TOKEN", "\"dt0c01.PROD_BIZEVENTS_TOKEN\"")
            buildConfigField("String", "DYNATRACE_LOGS_TOKEN", "\"dt0c01.PROD_LOGS_TOKEN\"")
        }
    }
}
```

```kotlin
// In BankingApplication.kt
private fun configureDynatraceIntegration() {
    DynatraceLogger.configure(
        endpoint = "${BuildConfig.DYNATRACE_TENANT}/api/v2/logs/ingest",
        apiToken = BuildConfig.DYNATRACE_LOGS_TOKEN,
        appName = "Banking-Android-App"
    )
    
    BusinessEventsClient.configure(
        BusinessEventsClient.Config(
            endpoint = "${BuildConfig.DYNATRACE_TENANT}/api/v2/bizevents/ingest",
            auth = BusinessEventsClient.Auth.ApiToken(BuildConfig.DYNATRACE_BIZEVENTS_TOKEN),
            eventProvider = "com.yourbank.banking.android",
            defaultEventType = "com.yourbank.user.action",
            appVersion = getAppVersion(),
            deviceInfo = getDeviceInfo()
        )
    )
}
```

## 6. User Journey Tracking

Track complete user journeys across multiple screens:

```kotlin
// LoginActivity.kt
class LoginActivity : AppCompatActivity() {
    
    private var userJourneyActionId: UUID? = null
    
    private fun startUserLogin() {
        // Start user journey tracking
        userJourneyActionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "User Login Journey",
                attributes = mapOf(
                    "login.method" to "email_password",
                    "app.version" to BuildConfig.VERSION_NAME
                )
            )
        )
    }
    
    private fun navigateToPaymentAfterLogin() {
        // Continue journey in payment screen
        val intent = Intent(this, PaymentActivity::class.java)
        intent.putExtra("parent_action_id", userJourneyActionId.toString())
        startActivity(intent)
    }
}

// PaymentActivity.kt - Continue the journey
class PaymentActivity : AppCompatActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val parentActionIdString = intent.getStringExtra("parent_action_id")
        val parentActionId = parentActionIdString?.let { UUID.fromString(it) }
        
        // Continue user journey with payment as child action
        if (parentActionId != null) {
            performPaymentAsPartOfJourney(parentActionId)
        }
    }
    
    private fun performPaymentAsPartOfJourney(parentActionId: UUID) {
        lifecycleScope.launch {
            BusinessEventsClient.withAction(
                name = "Payment Processing",
                parentActionId = parentActionId,
                attributes = mapOf("payment.screen" to "payment_activity")
            ) {
                // Payment logic...
            }
        }
    }
}
```

## 7. Error Handling and Monitoring

```kotlin
// Custom error handler for the banking app
class BankingErrorHandler {
    
    companion object {
        fun handleCriticalError(error: Throwable, context: String) {
            // Log to Dynatrace
            DynatraceLogger.critical(
                message = "Critical banking error occurred",
                tag = "BankingErrorHandler",
                throwable = error
            )
            
            // Track as business event
            lifecycleScope.launch {
                BusinessEventsClient.withAction(
                    name = "Critical Error",
                    attributes = mapOf(
                        "error.context" to context,
                        "error.type" to error.javaClass.simpleName,
                        "error.message" to (error.message ?: "Unknown error")
                    )
                ) {
                    // Additional error handling logic
                }
            }
        }
        
        fun handlePaymentError(error: String, transactionContext: Map<String, Any>) {
            DynatraceLogger.error("Payment error: $error", "PaymentErrorHandler")
            
            lifecycleScope.launch {
                BusinessEventsClient.withAction(
                    name = "Payment Error",
                    attributes = transactionContext + mapOf("error.details" to error)
                ) {
                    // Payment-specific error handling
                }
            }
        }
    }
}
```

## 8. Performance Monitoring

```kotlin
// Performance monitoring utility
class PerformanceMonitor {
    
    companion object {
        fun <T> measureOperation(
            operationName: String,
            attributes: Map<String, Any> = emptyMap(),
            operation: suspend () -> T
        ): T = runBlocking {
            BusinessEventsClient.withAction(
                name = operationName,
                attributes = attributes + mapOf("monitoring.type" to "performance")
            ) {
                val startTime = System.currentTimeMillis()
                try {
                    val result = operation()
                    val duration = System.currentTimeMillis() - startTime
                    DynatraceLogger.info(
                        "Operation '$operationName' completed in ${duration}ms",
                        "PerformanceMonitor"
                    )
                    result
                } catch (e: Exception) {
                    val duration = System.currentTimeMillis() - startTime
                    DynatraceLogger.error(
                        "Operation '$operationName' failed after ${duration}ms",
                        "PerformanceMonitor",
                        e
                    )
                    throw e
                }
            }
        }
    }
}

// Usage example
class AccountService {
    suspend fun loadAccountBalance(): AccountBalance {
        return PerformanceMonitor.measureOperation(
            operationName = "Load Account Balance",
            attributes = mapOf(
                "service" to "AccountService",
                "operation" to "balance_load"
            )
        ) {
            // Your account balance loading logic
            accountRepository.getBalance()
        }
    }
}
```

## 9. Updating PaymentLibrary AAR

When you make changes to the PaymentLibrary, you need to regenerate and update the AAR file:

### Step 1: Rebuild PaymentLibrary
```bash
cd PaymentLibrary-Android
./gradlew clean :PaymentLibrary:assembleRelease
```

### Step 2: Update AAR in Banking App
```bash
# Copy new AAR file to Banking App
cp PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar /path/to/your/BankingApp/app/libs/
```

### Step 3: Clean and Rebuild Banking App
```bash
cd /path/to/your/BankingApp
./gradlew clean build
```

**Important Notes:**
- Always clean build the Banking App after updating the AAR
- The AAR file size should be approximately 20-50KB for the PaymentLibrary
- Verify the AAR was updated by checking the file timestamp
- If you encounter `ClassNotFoundException`, ensure you've added all required dependencies

### Automated Update Script (Optional)
Create a script to automate AAR updates:

```bash
#!/bin/bash
# update_payment_library.sh

PAYMENT_LIB_PATH="/Users/igor.simoes/MobileDevelopment/PaymentLibrary/PaymentLibrary-Android"
BANKING_APP_PATH="/path/to/your/BankingApp"

echo "Building PaymentLibrary..."
cd "$PAYMENT_LIB_PATH"
./gradlew clean :PaymentLibrary:assembleRelease

echo "Copying AAR to Banking App..."
cp PaymentLibrary/build/outputs/aar/paymentlibrary-release.aar "$BANKING_APP_PATH/app/libs/"

echo "Rebuilding Banking App..."
cd "$BANKING_APP_PATH"
./gradlew clean build

echo "PaymentLibrary updated successfully!"
```

## 10. Testing

```kotlin
// Test configuration
class TestBankingApplication : BankingApplication() {
    
    override fun configureDynatraceIntegration() {
        // Use test configuration or disable for tests
        DynatraceLogger.configure(
            endpoint = "https://test.dynatrace.com/api/v2/logs/ingest",
            apiToken = "test-token",
            appName = "Banking-Android-Test"
        )
        
        // Configure with test endpoints
        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = "https://test.dynatrace.com/api/v2/bizevents/ingest",
                auth = BusinessEventsClient.Auth.ApiToken("test-token"),
                eventProvider = "com.yourbank.banking.test",
                defaultEventType = "com.yourbank.test.action"
            )
        )
    }
}
```

## 11. Verifying AAR Integration

### Check AAR Contents
You can inspect the AAR file contents to verify it includes all necessary classes:

```bash
# Extract AAR contents (AAR is just a ZIP file)
cd /path/to/your/BankingApp/app/libs
unzip -l paymentlibrary-release.aar

# Should show:
# AndroidManifest.xml
# classes.jar
# R.txt
# res/ (if any resources)
```

### Verify Integration in Banking App
Add this test method to verify the library is properly integrated:

```kotlin
// In your Banking App - TestActivity or test method
fun verifyPaymentLibraryIntegration() {
    try {
        // Test DynatraceLogger
        DynatraceLogger.info("Integration test", "TestActivity")
        
        // Test BusinessEventsClient
        val actionId = BusinessEventsClient.beginAction(
            actionName = "integration-test",
            attributes = mapOf("test" to "true")
        )
        BusinessEventsClient.endAction(actionId)
        
        // Test PaymentClient
        val paymentClient = PaymentClient()
        // paymentClient methods should be accessible
        
        Log.d("Integration", "PaymentLibrary integration successful!")
        
    } catch (e: Exception) {
        Log.e("Integration", "PaymentLibrary integration failed", e)
    }
}
```

### Common Issues and Solutions

1. **ClassNotFoundException**
   - Ensure all required dependencies are added to Banking App's `build.gradle.kts`
   - Clean and rebuild both projects

2. **NoSuchMethodError**
   - AAR might be outdated, regenerate it
   - Check that dependency versions match

3. **Import Issues**
   - Verify package names: `com.dynatracese.paymentlibrary.*`
   - Check that AAR is in correct `libs` folder

## 12. Best Practices

1. **AAR Management**:
   - Version your AAR files (e.g., `paymentlibrary-v1.2.3-release.aar`)
   - Keep AAR files in version control or artifact repository
   - Document which Banking App version uses which AAR version

2. **Development Workflow**:
   - Create update scripts to automate AAR regeneration
   - Test AAR integration before releasing to production
   - Use semantic versioning for PaymentLibrary changes

3. **Integration**:
   - Initialize early in Application.onCreate()
   - Use meaningful names for business events and logs
   - Add context with relevant attributes
   - Handle errors gracefully with try-catch blocks

4. **Security**:
   - Store Dynatrace tokens securely (BuildConfig, encrypted preferences)
   - Use different endpoints for dev/staging/production
   - Never commit tokens to version control

5. **Performance**:
   - Monitor AAR file size (should be 20-50KB)
   - Use business events to track operation durations
   - Implement proper coroutine scoping in Banking App

This AAR-based integration provides comprehensive monitoring of your banking app's payment flows while maintaining the same correlation and tracking capabilities as the iOS version.