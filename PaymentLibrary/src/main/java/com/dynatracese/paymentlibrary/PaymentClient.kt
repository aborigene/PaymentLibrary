//=============================================================================
// src/main/java/com/dynatracese/paymentlibrary/PaymentClient.kt
//
// Esta classe é a interface pública da biblioteca.
// Ela expõe as funcionalidades de receber e cancelar pagamentos.
//=============================================================================
package com.dynatracese.paymentlibrary

import android.util.Log
import com.dynatracese.paymentlibrary.api.PaymentService
import com.dynatracese.paymentlibrary.models.PaymentCancellationRequest
import com.dynatracese.paymentlibrary.models.PaymentRequest
import com.dynatracese.paymentlibrary.models.PaymentResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.lang.Exception
import java.util.UUID
import android.content.Context
import android.widget.Toast
import com.dynatrace.openkit.DynatraceOpenKitBuilder
import kotlin.random.Random
import com.dynatrace.openkit.api.OpenKit
//import com.dynatrace.openkit.core.DynatraceOpenKitBuilder
import com.dynatrace.openkit.api.Session
import com.dynatrace.openkit.api.Action

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

// A classe agora recebe a URL base como parâmetro do construtor
class PaymentClient(private val baseUrl: String, private val context: Context) {

    private val paymentService: PaymentService?
    private lateinit var session: Session

    init {
        // Replace with your Dynatrace tenant URL and application ID
        val tenantUrl = "https://bf78240axh.bf.dynatrace.com/mbeacon"
        val applicationId = ""
        val deviceId = 12323423423 // A unique identifier for the device

        val openKit = DynatraceOpenKitBuilder(tenantUrl, applicationId, deviceId)
            .build()
            .apply {
                // Wait until the OpenKit SDK is initialized
                waitForInitCompletion()
            }
        session = openKit.createSession("user@example.com")
        if (Random.nextInt(100) < 0) {
            // Log the event for debugging purposes
            Log.e("PaymentLibrary", "Simulating a crash for testing purposes.")
            // Throw an unhandled exception to cause a crash
            throw NullPointerException("Simulated Payment Library Crash")
        }
        // Se a URL for "TEST_ONLY", não inicializa o Retrofit
        if (baseUrl != "TEST_ONLY") {
            val retrofit = Retrofit.Builder()
                .baseUrl(baseUrl)
                .addConverterFactory(GsonConverterFactory.create())
                .build()

            paymentService = retrofit.create(PaymentService::class.java)
        } else {
            paymentService = null
        }
        PaymentCrashHandler.register(context.applicationContext)

        Log.d("PaymentLibrary", "PaymentLibrary initialized successfully.")
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
        callback: PaymentCallback
    ) {
        val action = session.enterAction("Payment Process")
        Log.i("PaymentClient", "Sending payment")
        withContext(Dispatchers.IO) {
            if (baseUrl == "TEST_ONLY") {
                // Simulação de pagamento para o modo de teste
                if (amount > 0) {
                    val transactionId = UUID.randomUUID().toString()
                    callback.onPaymentSuccess(transactionId)
                } else {
                    callback.onPaymentFailure("Simulated error: Amount must be positive.")
                }
            } else {
                // Lógica de chamada real para o backend
                try {
                    val paymentRequest = PaymentRequest(amount, creditCardNumber, vendorName, vendorId)
                    val response = paymentService?.receivePayment(paymentRequest)

                    if (response != null && response.isSuccessful) {
                        val transactionId = response.body()?.transactionId
                        if (transactionId != null) {
                            callback.onPaymentSuccess(transactionId)
                        } else {
                            callback.onPaymentFailure("Transaction ID not found in response.")
                        }
                    } else {
                        callback.onPaymentFailure("Payment failed with code: ${response?.code()}")
                    }
                } catch (e: Exception) {
                    Log.e("PaymentClient", "Error receiving payment", e)
                    callback.onPaymentFailure(e.message ?: "Unknown error")
                }
            }
        }
        action.leaveAction()
        Log.i("PaymentClient", "Finished Sending payment")
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
        withContext(Dispatchers.IO) {
            if (baseUrl == "TEST_ONLY") {
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