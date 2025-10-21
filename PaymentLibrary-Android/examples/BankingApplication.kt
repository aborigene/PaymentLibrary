// Example Banking App Application Class - BankingApplication.kt

package com.yourbank.bankingapp

import android.app.Application
import android.os.Build
import com.dynatracese.paymentlibrary.BusinessEventsClient
import com.dynatracese.paymentlibrary.DynatraceLogger

class BankingApplication : Application() {
    
    companion object {
        // Replace these with your actual Dynatrace tenant and tokens
        private const val DYNATRACE_TENANT = "https://abc12345.live.dynatrace.com"
        private const val BIZEVENTS_API_TOKEN = "dt0c01.ST2EY72KQINMH4J2CQZUYKX3.G3DFPBEJYMODIDAEX3CQZUYKX3LQCD2WETZ2SCZRQNFZ4WP3CQZUYKX3"
        private const val LOGS_API_TOKEN = "dt0c01.ST2EY72KQINMH4J2CQZUYKX3.H4DFPBEJYMODIDAEX3CQZUYKX3LQCD2WETZ2SCZRQNFZ4WP3CQZUYKX3"
    }
    
    override fun onCreate() {
        super.onCreate()
        
        // Configure Dynatrace integrations before any other operations
        configureDynatraceIntegration()
        
        // Log that the banking app has started
        DynatraceLogger.info("Banking Application started", "BankingApplication")
    }
    
    private fun configureDynatraceIntegration() {
        try {
            // 1. Configure DynatraceLogger for log ingestion
            // This replaces the SwiftyBeaver functionality from iOS
            DynatraceLogger.configure(
                endpoint = "$DYNATRACE_TENANT/api/v2/logs/ingest",
                apiToken = LOGS_API_TOKEN,
                appName = "Banking-Android-App"
            )
            
            // 2. Configure BusinessEventsClient for RUM monitoring
            // This provides the same functionality as the iOS BusinessEventsClient
            BusinessEventsClient.configure(
                BusinessEventsClient.Config(
                    endpoint = "$DYNATRACE_TENANT/api/v2/bizevents/ingest",
                    auth = BusinessEventsClient.Auth.ApiToken(BIZEVENTS_API_TOKEN),
                    eventProvider = "com.yourbank.banking.android", // Matches iOS pattern
                    defaultEventType = "com.yourbank.user.action",   // Matches iOS pattern
                    appVersion = getAppVersion(),
                    deviceInfo = getDeviceInfo()
                )
            )
            
            // Test that configuration worked
            DynatraceLogger.info("Dynatrace integration configured successfully", "BankingApplication")
            
        } catch (e: Exception) {
            // Fallback logging if Dynatrace configuration fails
            android.util.Log.e("BankingApplication", "Failed to configure Dynatrace integration", e)
            
            // Still configure with dummy values so app doesn't crash
            configureFallbackDynatrace()
        }
    }
    
    private fun configureFallbackDynatrace() {
        try {
            DynatraceLogger.configure(
                endpoint = "https://fallback.dynatrace.com/api/v2/logs/ingest",
                apiToken = "fallback-token",
                appName = "Banking-Android-App"
            )
            
            BusinessEventsClient.configure(
                BusinessEventsClient.Config(
                    endpoint = "https://fallback.dynatrace.com/api/v2/bizevents/ingest",
                    auth = BusinessEventsClient.Auth.ApiToken("fallback-token"),
                    eventProvider = "com.yourbank.banking.android",
                    defaultEventType = "com.yourbank.user.action"
                )
            )
        } catch (e: Exception) {
            android.util.Log.e("BankingApplication", "Even fallback configuration failed", e)
        }
    }
    
    private fun getAppVersion(): String {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        }
    }
    
    private fun getDeviceInfo(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
    }
}

/*
 * Don't forget to register this Application class in your AndroidManifest.xml:
 * 
 * <application
 *     android:name=".BankingApplication"
 *     android:allowBackup="true"
 *     android:icon="@mipmap/ic_launcher"
 *     android:label="@string/app_name"
 *     android:theme="@style/AppTheme">
 *     
 *     <activity
 *         android:name=".MainActivity"
 *         android:exported="true">
 *         <intent-filter>
 *             <action android:name="android.intent.action.MAIN" />
 *             <category android:name="android.intent.category.LAUNCHER" />
 *         </intent-filter>
 *     </activity>
 * </application>
 */