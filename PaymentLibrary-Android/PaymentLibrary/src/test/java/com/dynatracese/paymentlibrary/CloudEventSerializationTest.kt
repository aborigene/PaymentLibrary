package com.dynatracese.paymentlibrary

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test
import org.junit.Assert.*

class BusinessEventsClientSerializationTest {
    @Test
    fun `begin and end action does not throw serialization error`() {
        // Configure with dummy endpoint and token
        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = "https://localhost/mock", // No real network call
                auth = BusinessEventsClient.Auth.ApiToken("dummy-token"),
                eventProvider = "test-provider",
                appVersion = "1.0.0",
                deviceInfo = "Test Device",
                deviceMetadata = null
            )
        )

        // Use runBlocking to call suspend functions
        runBlocking {
            val actionId = BusinessEventsClient.beginAction(
                BusinessEventsClient.BeginOptions(name = "TestAction")
            )
            try {
                BusinessEventsClient.endAction(actionId, status = "SUCCESS")
            } catch (e: Exception) {
                // If the error is a SerializationException, fail the test
                if (e is kotlinx.serialization.SerializationException) {
                    fail("SerializationException: ${e.message}")
                }
                // Otherwise, ignore (e.g., network error)
            }
        }
    }
}
