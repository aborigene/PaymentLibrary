//=============================================================================
// src/main/java/com/dynatracese/paymentlibrary/Main.kt
//
// Exemplo de como usar a biblioteca em um projeto sem uma Activity.
// Este código pode ser executado em um ambiente de teste ou em um serviço em background.
//=============================================================================
package com.dynatracese.paymentlibrary

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID
import com.dynatracese.paymentlibrary.PaymentClient

fun main() {
//    println("Iniciando o exemplo de uso da PaymentLibrary...")
//
//    val client = PaymentClient("TEST_ONLY", this)
//    val coroutineScope = CoroutineScope(Dispatchers.Main)
//
//    // Exemplo de chamada para receber um pagamento
//    coroutineScope.launch {
//        client.receivePayment(
//            amount = 100.50,
//            creditCardNumber = "1234567890123456",
//            vendorName = "Loja de Exemplo",
//            vendorId = "vendor_01",
//            callback = object : PaymentCallback {
//                override fun onPaymentSuccess(transactionId: String) {
//                    println("Pagamento recebido com sucesso! Transaction ID: $transactionId")
//
//                    // Exemplo de chamada para cancelar o pagamento
//                    coroutineScope.launch {
//                        client.cancelPayment(
//                            transactionId = transactionId,
//                            callback = object : CancellationCallback {
//                                override fun onCancellationSuccess() {
//                                    println("Pagamento cancelado com sucesso!")
//                                }
//
//                                override fun onCancellationFailure(error: String) {
//                                    println("Erro ao cancelar o pagamento: $error")
//                                }
//                            }
//                        )
//                    }
//                }
//
//                override fun onPaymentFailure(error: String) {
//                    println("Erro ao receber pagamento: $error")
//                }
//            }
//        )
//    }
//
//    // Mantém a aplicação rodando por um tempo para as coroutines serem concluídas
//    Thread.sleep(5000)
//    println("Exemplo concluído.")
}