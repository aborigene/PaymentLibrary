//=============================================================================
// src/main/java/com/dynatracese/paymentlibrary/PaymentClient.kt
//
// Esta classe é a interface pública da biblioteca.
// Ela expõe as funcionalidades de receber e cancelar pagamentos.
//=============================================================================
package com.dynatracese.paymentlibrary

import android.util.Log
import android.os.Build
//import com.dynatracese.paymentlibrary.BuildConfig
import com.dynatracese.paymentlibrary.api.PaymentService
import com.dynatracese.paymentlibrary.models.PaymentCancellationRequest
import com.dynatracese.paymentlibrary.models.PaymentRequest
import com.dynatracese.paymentlibrary.models.PaymentResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.lang.Exception
import java.util.UUID
import android.content.Context
import android.widget.Toast
import kotlin.random.Random
import com.dynatracese.paymentlibrary.PaymentCrashHandler
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import java.io.PrintWriter
import java.io.StringWriter

// --- FIX: REMOVED UNNECESSARY IMPORTS ---
// Classes in the same package are automatically visible.
// ---------------------------------------


// Interface para callbacks de pagamento
interface PaymentCallback {
    fun onPaymentSuccess(transactionId: String)
    fun onPaymentFailure(error: String)
}

// Interface para callbacks de cancelamento
interface CancellationCallback {
    fun onCancellationSuccess()
    fun onCancellationFailure(error: String)
}

// A classe agora recebe um objeto Config e o Context
class PaymentClient private constructor(
    private val config: Config, // Use a Config object
    private val context: Context
) {

    /**
     * Unified configuration for the PaymentClient
     * @param paymentBaseUrl The base URL for the payment processing backend
     * @param bizeventsEventProvider Event provider string (e.g., "com.my-app.payment-library")
     * @param bizeventsDefaultEventType Default event type (e.g., "com.my-app.user-action")
     * @param appVersion The application version (optional)
     */
    data class Config(
        val paymentBaseUrl: String,
        val appVersion: String? = null
    )

    companion object {
        @Volatile
        private var INSTANCE: PaymentClient? = null

        // Updated getInstance to accept the new Config object
        fun getInstance(config: Config, context: Context): PaymentClient {
            // Use the application context to prevent memory leaks
            val appContext = context.applicationContext
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: PaymentClient(config, appContext).also { INSTANCE = it }
            }
        }
    }

    private val paymentService: PaymentService?

    init {
        // Register crash handler
        PaymentCrashHandler.register(context.applicationContext)

        // Initialize the BusinessEventsClient using the new Secrets-aware method
        Log.d("PaymentLibrary", "Initializing BusinessEventsClient from Secrets...")
        BusinessEventsClient.configureFromSecrets(
            context = context,
            eventProvider = "Android App", // Internal default, not customizable
            appVersion = config.appVersion
        )

        // Se a URL for "TEST_ONLY", não inicializa o Retrofit
        // Use config.paymentBaseUrl instead of baseUrl
        if (config.paymentBaseUrl != "TEST_ONLY") {
            val retrofit = Retrofit.Builder()
                .baseUrl(config.paymentBaseUrl) // Use config
                .addConverterFactory(GsonConverterFactory.create())
                .build()

            paymentService = retrofit.create(PaymentService::class.java)
        } else {
            paymentService = null
        }

        Log.d("PaymentLibrary", "PaymentLibrary initialized successfully.")
        DynatraceLogger.info("PaymentLibrary initialized successfully", "PaymentClient")
    }

    /**
     * Recebe um pagamento e retorna o ID da transação.
     * @param amount Valor do pagamento.
     * @param creditCardNumber Número do cartão de crédito.
     * @param vendorName Nome do fornecedor.
     * @param vendorId ID do fornecedor.
     */
    suspend fun receivePayment(
        amount: Double,
        creditCardNumber: String,
        vendorName: String,
        vendorId: String,
        callback: PaymentCallback,
        crashStatus: Boolean
    ) {
        // Use BusinessEventsClient to track the payment process
        BusinessEventsClient.withAction(
            name = "receivePayment",
            attributes = mapOf(
                "payment.amount" to amount,
                "payment.creditCardNumber" to creditCardNumber,
                "payment.vendorName" to vendorName,
                "payment.vendorId" to vendorId
            )
        ) {
            Log.i("receivePayment", "Starting payment process for amount $amount")
            DynatraceLogger.info("Starting payment processing", "PaymentClient")

            if (crashStatus) {
                DynatraceLogger.error("Simulating crash on purpose", "PaymentClient")
                throw Exception("Simulated Payment Library Crash")
            }

            // Execute both executePayment and dummyDoSomething in parallel
            Log.i("receivePayment", "Starting executePayment and dummyDoSomething in parallel")

            coroutineScope {
                val paymentDeferred = async {
                    executePayment(amount, creditCardNumber, vendorName, vendorId, callback)
                }

                val dummyDeferred = async {
                    dummyDoSomething()
                }

                // Wait for both operations to complete
                paymentDeferred.await()
                dummyDeferred.await()
            }

            Log.i("receivePayment", "Both executePayment and dummyDoSomething completed")

            // Add random delay like iOS version
            Log.i("receivePayment", "Starting to sleep...")
            val randomDelayMs = (700..3000).random().toLong()
            delay(randomDelayMs)
            Log.i("receivePayment", "Finished sleeping")
        }
    }

    private fun getLocalIpAddress(): String? {
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                val addrs = Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (ex: Exception) {
            // Handle exception
            Log.i("IP", "Was not able to get IP address...")
        }
        return null
    }

    private suspend fun executePayment(
        amount: Double,
        creditCardNumber: String,
        vendorName: String,
        vendorId: String,
        callback: PaymentCallback
    ) {
        BusinessEventsClient.withAction(
            name = "executePayment",
            attributes = mapOf(
                "payment.amount" to amount,
                "payment.creditCardNumber" to creditCardNumber,
                "payment.vendorName" to vendorName,
                "payment.vendorId" to vendorId
            )
        ) {
            Log.i("executePayment", "Inside executePayment method implementation")
            Log.i("executePayment", "Starting to sleep for latency simulation...")
            val randomDelayMs = (700..3000).random().toLong()
            delay(randomDelayMs)
            Log.i("executePayment", "Finished sleeping")

            // Use config.paymentBaseUrl
            if (config.paymentBaseUrl == "TEST_ONLY") {
                if (amount > 0) {
                    val transactionId = UUID.randomUUID().toString()
                    callback.onPaymentSuccess(transactionId)
                    Log.i("executePayment", "Payment successful in TEST_ONLY mode")
                } else {
                    callback.onPaymentFailure("Amount must be positive")
                    Log.w("executePayment", "Payment failed in TEST_ONLY mode: Amount not positive")
                }
                return@withAction
            }

            withContext(Dispatchers.IO) {
                try {
                    val paymentRequest = PaymentRequest(amount, creditCardNumber, vendorName, vendorId)
                    val response = paymentService?.receivePayment(paymentRequest)

                    if (response != null && response.isSuccessful) {
                        val transactionId = response.body()?.transactionId
                        if (transactionId != null) {
                            callback.onPaymentSuccess(transactionId)
                            Log.i("executePayment", "Payment completed. Transaction ID: $transactionId")
                        } else {
                            callback.onPaymentFailure("Transaction ID not found in response")
                            Log.e("executePayment", "Failed to get transaction ID from response")
                        }
                    } else {
                        val statusCode = response?.code() ?: 0
                        callback.onPaymentFailure("HTTP $statusCode")
                        Log.e("executePayment", "Payment API call failed with HTTP status code: $statusCode")
                    }
                } catch (e: Exception) {
                    callback.onPaymentFailure(e.message ?: "Unknown error")
                    Log.e("executePayment", "Payment network request failed: ${e.message}")
                }
            }
        }
    }

    private suspend fun dummyDoSomething() {
        BusinessEventsClient.withAction(name = "dummyDoSomething") { // Renamed action
            Log.v("PaymentClient", "Started dummyDoSomething")
            val randomDelayMs = (700..3000).random().toLong()
            delay(randomDelayMs)
            dummyDoSomethingElse()
            Log.v("PaymentClient", "Finished dummyDoSomething")
        }
    }

    private suspend fun dummyDoSomethingElse() {
        BusinessEventsClient.withAction(name = "dummyDoSomethingElse") { // Renamed action
            Log.v("PaymentClient", "Started dummyDoSomethingElse")
            val randomDelayMs = (700..3000).random().toLong()
            delay(randomDelayMs)
            dummyDoSomethingMore()
            Log.v("PaymentClient", "Finished dummyDoSomethingElse")
        }
    }

    private suspend fun dummyDoSomethingMore() {
        BusinessEventsClient.withAction(name = "dummyDoSomethingMore") {
            Log.v("PaymentClient", "Started dummyDoSomethingMore")
            val randomDelayMs = (700..3000).random().toLong()
            delay(randomDelayMs)
            Log.v("PaymentClient", "Finished dummyDoSomethingMore")
        }
    }

    /**
     * Cancela um pagamento.
     * @param transactionId ID da transação a ser cancelada.
     * @param callback Callback para tratar o sucesso ou a falha.
     */
    suspend fun cancelPayment(
        transactionId: String,
        callback: CancellationCallback
    ) {
        // Use config.paymentBaseUrl
        withContext(Dispatchers.IO) {
            if (config.paymentBaseUrl == "TEST_ONLY") {
                // Simulação de cancelamento para o modo de teste
                if (transactionId.isNotEmpty()) {
                    callback.onCancellationSuccess()
                } else {
                    callback.onCancellationFailure("Simulated error: Transaction ID is empty.")
                }
            } else {
                // Lógica de chamada real para o backend
                try {
                    val cancellationRequest = PaymentCancellationRequest(transactionId)
                    val response = paymentService?.cancelPayment(cancellationRequest)

                    if (response != null && response.isSuccessful) {
                        callback.onCancellationSuccess()
                    } else {
                        callback.onCancellationFailure("Cancellation failed with code: ${response?.code()}")
                    }
                } catch (e: Exception) {
                    Log.e("PaymentClient", "Error canceling payment", e)
                    callback.onCancellationFailure(e.message ?: "Unknown error")
                }
            }
        }
    }
}