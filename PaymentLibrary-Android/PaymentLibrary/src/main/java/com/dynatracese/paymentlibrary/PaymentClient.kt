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
import com.dynatrace.openkit.api.LogLevel
import com.dynatracese.paymentlibrary.PaymentCrashHandler
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import java.io.PrintWriter
import java.io.StringWriter


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
class PaymentClient private constructor(private val baseUrl: String, private val context: Context) {

    companion object {
        @Volatile
        private var INSTANCE: PaymentClient? = null

        fun getInstance(baseUrl: String, context: Context): PaymentClient {
            // Use the application context to prevent memory leaks
            val appContext = context.applicationContext
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: PaymentClient(baseUrl, appContext).also { INSTANCE = it }
            }
        }
    }

    private val paymentService: PaymentService?
    private lateinit var session: Session
    //private var crashStatus: Boolean = crashStatus

    init {
        // Replace with your Dynatrace tenant URL and application ID

        if(!this::session.isInitialized){
            val tenantUrl = "https://bf78240axh.bf.dynatrace.com/mbeacon"
            val applicationId = "b29101f0-9a10-44bb-9ae8-f024f0ec657a"
            val deviceId = 12323423423 // A unique identifier for the device
            val operatingSystem = "Android "+Build.VERSION.RELEASE+ " (API "+ Build.VERSION.SDK_INT+")"
            val openKit = DynatraceOpenKitBuilder(tenantUrl, applicationId, deviceId)
                .withApplicationVersion("1.0")
                .withOperatingSystem(operatingSystem)
                .withManufacturer(Build.MANUFACTURER)
                .withModelID(Build.MODEL)
                .withLogLevel(LogLevel.DEBUG)
                .build()
                .apply {
                    // Wait until the OpenKit SDK is initialized
                    waitForInitCompletion()
                }
            session = openKit.createSession(getLocalIpAddress())
            val userName = UUID.randomUUID().toString()
            Log.i("OpenKit", "Session identified with user "+ userName)
            session.identifyUser(userName+"@example.com")
            PaymentCrashHandler.register(context.applicationContext, session)
            Log.i("OpenKit", "Session initialized:" + session.toString())
        }

        Log.i("OpenKit", "This is the session:" + session.toString())

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
        callback: PaymentCallback,
        crashStatus: Boolean
    ) {
        val action = session.enterAction("Payment Process")
        Log.i("receivePayment", "Starting send payment")
        Log.i("OpenKit", "This is the session:"+session.toString())
        Log.i("OpenKit", "This is the action:"+action.toString())
        executePayment(amount, creditCardNumber, vendorName, vendorId, callback, crashStatus)
        action.leaveAction()
        Log.i("receivePayment", "Finished Sending payment")
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
        callback: PaymentCallback,
        crashStatus: Boolean
    ){
        Log.i("executePayment", "Starting send payment")
        if (crashStatus){//(Random.nextInt(100) < 50) {
            // Log the event for debugging purposes
            Log.e("PaymentLibrary", "Simulating a crash for testing purposes.")
            val sw = StringWriter()
            val pw = PrintWriter(sw)
            Throwable().printStackTrace(pw)
            session.reportCrash(Throwable())
            Thread.sleep(2000)
            // Throw an unhandled exception to cause a crash
            throw NullPointerException("Simulated Payment Library Crash")
        }
        else{
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
        }

        Log.i("executePayment", "Finished Sending payment")
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