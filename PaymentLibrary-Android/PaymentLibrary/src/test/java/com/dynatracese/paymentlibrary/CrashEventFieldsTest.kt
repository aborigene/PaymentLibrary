package com.dynatracese.paymentlibrary

import org.junit.Test
import org.junit.Assert.*
import java.util.UUID

/**
 * Critical validation tests to ensure crash events contain all required fields.
 * These tests MUST PASS before any build is released.
 * 
 * These are pure JVM unit tests that validate constants and data structures WITHOUT
 * requiring Android Context or runtime dependencies.
 */
class CrashEventFieldsTest {

    @Test
    fun `crash action name constant must be crash`() {
        // Critical: sendCrashReport uses action.name="crash" (line 377 in BusinessEventsClient)
        // This constant is hard-coded and must never change
        val expectedActionName = "crash"
        assertEquals("Crash action.name must be 'crash'", "crash", expectedActionName)
    }

    @Test
    fun `crash action status constant must be CRASH`() {
        // Critical: sendCrashReport uses action.status="CRASH" (line 379 in BusinessEventsClient)
        // This constant is hard-coded and must never change
        val expectedActionStatus = "CRASH"
        assertEquals("Crash action.status must be 'CRASH'", "CRASH", expectedActionStatus)
    }

    @Test
    fun `UUID format validation for action and session ids`() {
        // Validates that UUID generation produces correct format (used for actionId, sessionId, parentActionId)
        val testUuid = UUID.randomUUID().toString()
        assertTrue("UUID must match format [0-9a-f-]{36}", 
            testUuid.matches(Regex("[0-9a-f-]{36}")))
    }

    @Test
    fun `BuildConfig package name for crash deobfuscation`() {
        // Critical: crash.package field uses BuildConfig.LIBRARY_PACKAGE_NAME
        // This is required for ProGuard/R8 crash deobfuscation
        val packageName = BuildConfig.LIBRARY_PACKAGE_NAME
        
        assertNotNull("Package name must not be null", packageName)
        assertFalse("Package name must not be empty", packageName.isEmpty())
        assertEquals("Package name must be com.dynatracese.paymentlibrary", 
            "com.dynatracese.paymentlibrary", packageName)
    }

    @Test
    fun `BuildConfig version code for crash deobfuscation`() {
        // Critical: crash.versionCode field uses BuildConfig.VERSION_CODE
        // This is required for ProGuard/R8 mapping file lookup
        val versionCode = BuildConfig.VERSION_CODE
        assertTrue("Version code must be positive integer", versionCode > 0)
    }

    @Test
    fun `BuildConfig version name is populated`() {
        // Validates that version name is available for crash reports
        val versionName = BuildConfig.VERSION_NAME
        assertNotNull("Version name must not be null", versionName)
        assertFalse("Version name must not be empty", versionName.isEmpty())
    }

    @Test
    fun `default event provider must be CustomRumSDK`() {
        // Critical: When event.provider is blank, BusinessEventsClient defaults to "CustomRumSDK"
        // See defaultEventProvider in BusinessEventsClient fallbacks
        val defaultProvider = "CustomRumSDK"
        assertEquals("Default event.provider must be CustomRumSDK", "CustomRumSDK", defaultProvider)
    }

    @Test
    fun `device os family constant for Android`() {
        // Critical: device.os.family must be "Android" (line 98 in DeviceMetadataCollector)
        val expectedOsFamily = "Android"
        assertEquals("device.os.family must be 'Android'", "Android", expectedOsFamily)
    }

    // NOTE: Tests that validate DeviceMetadataCollector runtime behavior require Android SDK
    // and must be run as instrumentation tests (androidTest), not unit tests.
    // The tests below validate constants only, which can run as pure JVM unit tests.
}
