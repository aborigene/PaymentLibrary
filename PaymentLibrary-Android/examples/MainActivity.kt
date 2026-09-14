// Example Banking App MainActivity.kt - Complete Integration Example

package com.yourbank.bankingapp

import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger
import com.dynatracese.paymentlibrary.PaymentCallback
import com.dynatracese.paymentlibrary.PaymentClient
import kotlinx.coroutines.launch
import java.util.UUID

class MainActivity : AppCompatActivity() {
    
    private lateinit var paymentClient: PaymentClient
    private lateinit var amountEditText: EditText
    private lateinit var cardNumberEditText: EditText
    private lateinit var merchantEditText: EditText
    private lateinit var payButton: Button
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        
        // Initialize PaymentClient with new Config (version collected automatically)
        paymentClient = PaymentClient.getInstance(
            config = PaymentClient.Config(
                paymentBaseUrl = "https://api.yourbank.com" // Your actual payment API
            ),
            context = this
        )
        
        initializeViews()
        setupPaymentButton()
        
        DynatraceLogger.info("Banking App MainActivity created", "MainActivity")
    }
    
    private fun initializeViews() {
        amountEditText = findViewById(R.id.amountEditText)
        cardNumberEditText = findViewById(R.id.cardNumberEditText)
        merchantEditText = findViewById(R.id.merchantEditText)
        payButton = findViewById(R.id.payButton)
        
        // Set some default values for easy testing
        amountEditText.setText("99.99")
        cardNumberEditText.setText("4111111111111111") // Test card number
        merchantEditText.setText("YourBank Store")
    }
    
    private fun setupPaymentButton() {
        payButton.setOnClickListener {
            val amount = amountEditText.text.toString().toDoubleOrNull()
            val cardNumber = cardNumberEditText.text.toString()
            val merchant = merchantEditText.text.toString()
            
            if (amount != null && cardNumber.isNotEmpty() && merchant.isNotEmpty()) {
                processPayment(amount, cardNumber, merchant)
            } else {
                Toast.makeText(this, "Please fill in all fields correctly", Toast.LENGTH_SHORT).show()
                DynatraceLogger.warning("Invalid payment form data", "MainActivity")
            }
        }
    }
    
    private fun processPayment(amount: Double, cardNumber: String, merchant: String) {
        lifecycleScope.launch {
            // Track the entire banking payment flow with BusinessEventsClient
            BusinessEventsClient.withAction(
                name = "Banking Payment Transaction",
                attributes = mapOf(
                    "payment.amount" to amount,
                    "payment.merchant" to merchant,
                    "payment.method" to "credit_card",
                    "app.screen" to "main_activity",
                    "user.session_id" to generateSessionId()
                )
            ) {
                try {
                    DynatraceLogger.info(
                        "Starting payment transaction for amount: $amount", 
                        "MainActivity"
                    )
                    
                    // Disable button during processing
                    runOnUiThread {
                        payButton.isEnabled = false
                        payButton.text = "Processing..."
                    }
                    
                    // Call PaymentLibrary (which now has its own BusinessEvents tracking)
                    paymentClient.receivePayment(
                        amount = amount,
                        creditCardNumber = cardNumber,
                        vendorName = merchant,
                        vendorId = "BANK_${System.currentTimeMillis()}", // Generate unique vendor ID
                        callback = object : PaymentCallback {
                            override fun onPaymentSuccess(transactionId: String) {
                                handlePaymentSuccess(transactionId, amount, merchant)
                            }
                            
                            override fun onPaymentFailure(error: String) {
                                handlePaymentFailure(error, amount, merchant)
                            }
                        },
                        crashStatus = false // Set to true if you want to test crash handling
                    )
                    
                } catch (e: Exception) {
                    DynatraceLogger.error("Payment processing exception", "MainActivity", e)
                    runOnUiThread {
                        payButton.isEnabled = true
                        payButton.text = "Pay Now"
                        Toast.makeText(this@MainActivity, "Payment error: ${e.message}", Toast.LENGTH_LONG).show()
                    }
                    throw e // Re-throw so BusinessEventsClient marks the action as ERROR
                }
            }
        }
    }
    
    private fun handlePaymentSuccess(transactionId: String, amount: Double, merchant: String) {
        DynatraceLogger.info(
            "Payment successful - Transaction ID: $transactionId, Amount: $amount", 
            "MainActivity"
        )
        
        // Track successful payment as a separate business event for analytics
        lifecycleScope.launch {
            BusinessEventsClient.withAction(
                name = "Payment Success Confirmation",
                attributes = mapOf(
                    "transaction.id" to transactionId,
                    "transaction.amount" to amount,
                    "transaction.merchant" to merchant,
                    "transaction.status" to "completed",
                    "confirmation.timestamp" to System.currentTimeMillis()
                )
            ) {
                runOnUiThread {
                    payButton.isEnabled = true
                    payButton.text = "Pay Now"
                    
                    Toast.makeText(
                        this@MainActivity,
                        "✅ Payment Successful!\nTransaction ID: $transactionId",
                        Toast.LENGTH_LONG
                    ).show()
                    
                    // Clear form after successful payment
                    clearPaymentForm()
                }
            }
        }
    }
    
    private fun handlePaymentFailure(error: String, amount: Double, merchant: String) {
        DynatraceLogger.error(
            "Payment failed - Amount: $amount, Merchant: $merchant, Error: $error", 
            "MainActivity"
        )
        
        // Track failed payment as a separate business event for analytics
        lifecycleScope.launch {
            BusinessEventsClient.withAction(
                name = "Payment Failure Analysis",
                attributes = mapOf(
                    "failure.reason" to error,
                    "failure.amount" to amount,
                    "failure.merchant" to merchant,
                    "failure.timestamp" to System.currentTimeMillis(),
                    "retry.available" to true
                )
            ) {
                runOnUiThread {
                    payButton.isEnabled = true
                    payButton.text = "Retry Payment"
                    
                    Toast.makeText(
                        this@MainActivity,
                        "❌ Payment Failed\n$error\n\nPlease try again",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }
    
    private fun clearPaymentForm() {
        amountEditText.setText("")
        cardNumberEditText.setText("")
        merchantEditText.setText("")
        payButton.text = "Pay Now"
    }
    
    private fun generateSessionId(): String {
        return "session_${System.currentTimeMillis()}_${(1000..9999).random()}"
    }
    
    override fun onResume() {
        super.onResume()
        DynatraceLogger.debug("MainActivity resumed", "MainActivity")
    }
    
    override fun onPause() {
        super.onPause()
        DynatraceLogger.debug("MainActivity paused", "MainActivity")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        DynatraceLogger.debug("MainActivity destroyed", "MainActivity")
    }
}

/*
 * Corresponding layout file: res/layout/activity_main.xml
 * 
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Banking App - Payment Demo"
        android:textSize="24sp"
        android:textStyle="bold"
        android:layout_gravity="center"
        android:layout_marginBottom="32dp" />

    <com.google.android.material.textfield.TextInputLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="16dp">
        
        <EditText
            android:id="@+id/amountEditText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Amount (e.g., 99.99)"
            android:inputType="numberDecimal" />
    </com.google.android.material.textfield.TextInputLayout>

    <com.google.android.material.textfield.TextInputLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="16dp">
        
        <EditText
            android:id="@+id/cardNumberEditText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Card Number"
            android:inputType="number" />
    </com.google.android.material.textfield.TextInputLayout>

    <com.google.android.material.textfield.TextInputLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginBottom="32dp">
        
        <EditText
            android:id="@+id/merchantEditText"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Merchant Name" />
    </com.google.android.material.textfield.TextInputLayout>

    <Button
        android:id="@+id/payButton"
        android:layout_width="match_parent"
        android:layout_height="60dp"
        android:text="Pay Now"
        android:textSize="18sp"
        android:textStyle="bold" />

</LinearLayout>
 */