### What this is

This is a sample library to be imported into an Android application. 
This sample library will enable the Android application
to use payment functions exposed by the library.

This is specifically to simulate a library being instrumented and providing telemetry data to Dynatrace
independently of whatever agent the main applications is using.

### How to use this library

#### Build

For some reason Android Studio may not expose the necessary commands, but they can still be executed from the terminal, follow the steps below:

1. From the root folder of this repo run the following command:
   2. `./gradlew :PaymentLibrary:assembleRelease`
3. This will generate the `*.aar` for the library
4. Copy the library to your application project folder structure:
   5. `cp ..../<PaymentLibraryRootFolder>/PaymentLibrary/build/outputs/aar/PaymentLibrary-release.aar ..../MainApplicationProjectRootFolder/app/libs`
   6. Adjust the directory names accordingly
7. On your main project add this to the build.gradle.kts dependency block:
   8. `implementation(files("libs/paymentlibrary-release.aar"))`
   9. This will make your library available and then it can be used on the code.

#### How to use the library on your code

Add the entries below to the file where you want to use the library:

```kotlin
import com.dynatracese.paymentlibrary.CancellationCallback
import com.dynatracese.paymentlibrary.PaymentCallback
import com.dynatracese.paymentlibrary.PaymentClient
```

##### Initialization (Updated in v1.0+)

**New Configuration-Based Initialization:**

The PaymentClient now requires configuration for proper Dynatrace integration and automatic version tracking:

```kotlin
val paymentClient = PaymentClient.getInstance(
    config = PaymentClient.Config(
        paymentBaseUrl = "TEST_ONLY"
    ),
    context = this
)
```

**Important Notes:**
- `appVersion` is **automatically collected** from the library's `BuildConfig.VERSION_NAME`
- This ensures correct deobfuscation in Dynatrace by using the library version, not the app version
- The library version is set internally and cannot be overridden

**Legacy Initialization (Pre-v1.0 - Deprecated):**

```kotlin
// ❌ OLD WAY - No longer supported
val paymentClient = PaymentClient("TEST_ONLY", this)
```

If you use the "TEST_ONLY" keyword no call will be made to a backend, this is the standard right now as the backend for this library has not been built yet,
in the future the endpoint for the API should be used and a request to backend should be made to actually make a payment.

To actually receive a payment the block below serves as an example:

```kotlin
paymentClient.receivePayment(
    amount = amount,
    creditCardNumber = creditCard,
    vendorName = "Loja de Exemplo",
    vendorId = "vendor_02",
    callback = object : PaymentCallback {
        override fun onPaymentSuccess(transactionId: String) {
            // Payment was successful
            // Update balance, show success message, or navigate back
            Toast.makeText(
                this@PaymentActivity, 
                "Payment successful! ID: $transactionId", 
                Toast.LENGTH_LONG
            ).show()
        }

        override fun onPaymentFailure(error: String) {
            // Payment error occurred
            // Display error message to user
            Toast.makeText(
                this@PaymentActivity, 
                "Payment failed: $error", 
                Toast.LENGTH_LONG
            ).show()
        }
    }
)
```

### Dynatrace Integration

The library automatically integrates with Dynatrace for:
- **Business Events Tracking**: All payment operations are tracked as business events
- **Error Monitoring**: Failures and exceptions are automatically reported
- **Crash Reporting**: Crash data with proper symbolication support
- **Custom Logging**: Direct log ingestion to Dynatrace

**Library Version Tracking:**
The library version (`BuildConfig.VERSION_NAME`) is automatically collected and sent with all telemetry data. This ensures:
- Correct stack trace deobfuscation in Dynatrace
- Accurate correlation between crashes and library versions
- No risk of version mismatch between app and library

For detailed integration with your Banking App, see [BANKING_APP_INTEGRATION_GUIDE.md](BANKING_APP_INTEGRATION_GUIDE.md).
