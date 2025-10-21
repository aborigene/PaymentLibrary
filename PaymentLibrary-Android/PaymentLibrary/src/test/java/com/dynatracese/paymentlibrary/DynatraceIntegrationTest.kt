package com.dynatracese.paymentlibrary

import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.Assert.*
import java.util.UUID

/**
 * Unit tests for BusinessEventsClient to verify basic functionality
 */
class BusinessEventsClientTest {

    @Test
    fun testBusinessEventsClientConfiguration() {
        // Test configuration
        val config = BusinessEventsClient.Config(
            endpoint = "https://test.dynatrace.com/api/v2/bizevents/ingest",
            auth = BusinessEventsClient.Auth.ApiToken("test-token"),
            eventProvider = "test.provider",
            defaultEventType = "test.event",
            appVersion = "1.0.0",
            deviceInfo = "Test Device"
        )
        
        BusinessEventsClient.configure(config)
        
        // Test beginAction returns a valid UUID
        val actionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "Test Action",
                attributes = mapOf("test" to "value")
            )
        )
        
        assertNotNull(actionId)
        assertTrue(actionId is UUID)
    }

    @Test
    fun testParentChildActionHierarchy() {
        // Configure BusinessEventsClient
        val config = BusinessEventsClient.Config(
            endpoint = "https://test.dynatrace.com/api/v2/bizevents/ingest",
            auth = BusinessEventsClient.Auth.ApiToken("test-token"),
            eventProvider = "test.provider",
            defaultEventType = "test.event"
        )
        
        BusinessEventsClient.configure(config)
        
        // Test parent action
        val parentActionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "Parent Action"
            )
        )
        
        // Test child action with parent
        val childActionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "Child Action",
                parentActionId = parentActionId
            )
        )
        
        assertNotNull(parentActionId)
        assertNotNull(childActionId)
        assertNotEquals(parentActionId, childActionId)
    }

    @Test
    fun testActionAttributes() {
        // Configure BusinessEventsClient
        val config = BusinessEventsClient.Config(
            endpoint = "https://test.dynatrace.com/api/v2/bizevents/ingest",
            auth = BusinessEventsClient.Auth.ApiToken("test-token"),
            eventProvider = "test.provider",
            defaultEventType = "test.event"
        )
        
        BusinessEventsClient.configure(config)
        
        // Test action with attributes
        val actionId = BusinessEventsClient.beginAction(
            BusinessEventsClient.BeginOptions(
                name = "Test Action with Attributes",
                attributes = mapOf(
                    "string_attr" to "test_value",
                    "number_attr" to 123,
                    "boolean_attr" to true
                )
            )
        )
        
        assertNotNull(actionId)
    }
}

/**
 * Unit tests for DynatraceLogger to verify basic functionality
 */
class DynatraceLoggerTest {

    @Test
    fun testDynatraceLoggerWithoutConfiguration() {
        // Test logging methods without configuration (should not throw exceptions)
        // This simulates the case when DynatraceLogger is not configured yet
        DynatraceLogger.info("Test info message", "TestTag")
        DynatraceLogger.debug("Test debug message", "TestTag")
        DynatraceLogger.error("Test error message", "TestTag", RuntimeException("Test exception"))
        
        // If we reach here without exceptions, the test passes
        assertTrue(true)
    }

    @Test
    fun testLogLevels() {
        // Test all log levels
        val levels = DynatraceLogger.LogLevel.values()
        
        assertEquals(6, levels.size)
        assertEquals("VERBOSE", DynatraceLogger.LogLevel.VERBOSE.value)
        assertEquals("DEBUG", DynatraceLogger.LogLevel.DEBUG.value)
        assertEquals("INFO", DynatraceLogger.LogLevel.INFO.value)
        assertEquals("WARNING", DynatraceLogger.LogLevel.WARNING.value)
        assertEquals("ERROR", DynatraceLogger.LogLevel.ERROR.value)
        assertEquals("CRITICAL", DynatraceLogger.LogLevel.CRITICAL.value)
    }
}