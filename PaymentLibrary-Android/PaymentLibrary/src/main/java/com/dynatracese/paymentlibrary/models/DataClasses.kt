//=============================================================================
// src/main/java/com/dynatracese/paymentlibrary/models/DataClasses.kt
//
// Estas classes de dados representam o corpo da requisição e da resposta.
//=============================================================================
package com.dynatracese.paymentlibrary.models

data class PaymentRequest(
    val amount: Double,
    val creditCardNumber: String,
    val vendorName: String,
    val vendorId: String
)

data class PaymentResponse(
    val transactionId: String
)

data class PaymentCancellationRequest(
    val transactionId: String
)