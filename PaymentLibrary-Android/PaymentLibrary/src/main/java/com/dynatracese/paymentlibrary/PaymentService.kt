//=============================================================================
// src/main/java/com/dynatracese/paymentlibrary/api/PaymentService.kt
//
// Esta interface define os endpoints da API REST usando Retrofit.
//=============================================================================
package com.dynatracese.paymentlibrary.api

import com.dynatracese.paymentlibrary.models.PaymentCancellationRequest
import com.dynatracese.paymentlibrary.models.PaymentResponse
import com.dynatracese.paymentlibrary.models.PaymentRequest
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.POST

interface PaymentService {
    @POST("payments/receive")
    suspend fun receivePayment(@Body paymentRequest: PaymentRequest): Response<PaymentResponse>

    @POST("payments/cancel")
    suspend fun cancelPayment(@Body cancellationRequest: PaymentCancellationRequest): Response<Void>
}