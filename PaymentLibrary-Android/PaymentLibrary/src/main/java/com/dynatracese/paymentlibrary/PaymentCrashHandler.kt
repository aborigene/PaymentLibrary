package com.dynatracese.paymentlibrary

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.util.*
import kotlin.system.exitProcess
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
class PaymentCrashHandler(private val context: Context, private val originalHandler: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {

    companion object {
        private var instance: PaymentCrashHandler? = null
        
        // Flag to prevent duplicate crash reports
        @Volatile
        private var crashReported = false

        fun register(context: Context) {
            val originalHandler = Thread.getDefaultUncaughtExceptionHandler()
            if (originalHandler !is PaymentCrashHandler) {
                instance = PaymentCrashHandler(context, originalHandler)
                Thread.setDefaultUncaughtExceptionHandler(instance)
                Log.i("registered status", "register: registered successfully")
                
                // Send any saved crash reports from previous crashes
                sendSavedCrashReports(context)
            }
        }
        
        private fun sendSavedCrashReports(context: Context) {
            val crashFile = File(context.filesDir, "crash_report.json")
            if (!crashFile.exists()) return
            
            Log.i("PaymentCrashHandler", "📤 Found saved crash report, sending...")
            
            try {
                val crashJson = crashFile.readText()
                val crashData = JSONObject(crashJson)
                
                val extraAttributes = mutableMapOf<String, Any>(
                    "saved_report" to true,
                    "device" to android.os.Build.MODEL
                )
                
                if (crashData.has("crash.class")) {
                    extraAttributes["crash.class"] = crashData.getString("crash.class")
                }
                if (crashData.has("crash.stackTrace")) {
                    extraAttributes["crash.stackTrace"] = crashData.getString("crash.stackTrace")
                }
                
                val errorMessage = if (crashData.has("action.error")) crashData.getString("action.error") else null
                val parentActionId = if (crashData.has("parentActionId") && !crashData.isNull("parentActionId")) {
                    UUID.fromString(crashData.getString("parentActionId"))
                } else null
                val sessionId = if (crashData.has("sessionId")) crashData.getString("sessionId") else BusinessEventsClient.sessionId
                
                runBlocking {
                    try {
                        BusinessEventsClient.sendCrashReport(
                            parentActionId = parentActionId,
                            sessionId = sessionId,
                            error = errorMessage,
                            extraAttributes = extraAttributes
                        )
                        // Delete file after successful send
                        crashFile.delete()
                        Log.i("PaymentCrashHandler", "✅ Saved crash report sent and deleted")
                    } catch (e: Exception) {
                        Log.e("PaymentCrashHandler", "❌ Failed to send saved crash report: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e("PaymentCrashHandler", "Failed to parse saved crash report: ${e.message}")
            }
        }

        fun reportCrash(context: Context, throwable: Throwable) {
            // Prevent duplicate crash reports
            if (crashReported) {
                Log.w("PaymentCrashHandler", "⚠️ CRASH ALREADY REPORTED - Skipping duplicate")
                return
            }
            crashReported = true
            
            val sw = StringWriter()
            val pw = PrintWriter(sw)
            throwable.printStackTrace(pw)
            val stackTrace = sw.toString()
            val description = throwable.message
            
            // Get current action context
            val actionContext = BusinessEventsClient.getCurrentActionContext()
            val sessionId = BusinessEventsClient.sessionId
            
            // Save crash data as JSON FIRST
            val crashData = JSONObject().apply {
                put("crash.class", throwable.javaClass.simpleName)
                put("crash.stackTrace", stackTrace)
                put("action.error", description ?: "unknown")
                put("parentActionId", actionContext?.id?.toString())
                put("sessionId", sessionId)
            }
            
            val crashFile = File(context.filesDir, "crash_report.json")
            try {
                crashFile.writeText(crashData.toString())
                Log.i("PaymentCrashHandler", "💾 Crash data saved to disk")
            } catch (e: Exception) {
                Log.e("PaymentCrashHandler", "Failed to save crash data: ${e.message}")
            }
            
            var crashSentSuccessfully = false
            
            // If there's an open action, finish it with CRASH status first
            actionContext?.let { ctx ->
                try {
                    runBlocking {
                        BusinessEventsClient.endAction(
                            actionId = ctx.id,
                            status = "CRASH",
                            error = description
                        )
                    }
                    Log.i("PaymentCrashHandler", "✅ Open action finished with CRASH status")
                } catch (e: Exception) {
                    Log.e("PaymentCrashHandler", "❌ Failed to finish open action: ${e.message}")
                }
            }
            
            // Now send the crash report
            val parentActionId = actionContext?.id
            val extraAttributes = mapOf(
                "crash.class" to throwable.javaClass.simpleName,
                "crash.stackTrace" to stackTrace,
                "device" to android.os.Build.MODEL
            )
            
            try {
                runBlocking {
                    BusinessEventsClient.sendCrashReport(
                        parentActionId = parentActionId,
                        sessionId = sessionId,
                        error = description,
                        extraAttributes = extraAttributes
                    )
                }
                Log.i("PaymentCrashHandler", "✅ Crash report sent successfully")
                crashSentSuccessfully = true
            } catch (e: Exception) {
                Log.e("PaymentCrashHandler", "❌ Failed to send crash report: ${e.message}", e)
            }
            
            // Delete saved report only if we successfully sent it
            if (crashSentSuccessfully) {
                crashFile.delete()
                Log.i("PaymentCrashHandler", "✅ Saved crash report deleted after successful send")
            } else {
                Log.w("PaymentCrashHandler", "⚠️ Crash report saved to disk for next reboot")
            }
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        // Prevent duplicate crash reports
        if (crashReported) {
            Log.w("PaymentCrashHandler", "⚠️ CRASH ALREADY REPORTED - Skipping duplicate")
            return
        }
        crashReported = true
        
        Log.i("PaymentCrashHandler", "🔴 CRASH HANDLER CALLED - Exception: ${throwable.javaClass.simpleName}")
        
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        throwable.printStackTrace(pw)
        val stackTrace = sw.toString()
        val description = throwable.message
        
        Log.i("PaymentCrashHandler", "🔴 StackTrace:\n$stackTrace")
        
        // Get current action context
        val actionContext = BusinessEventsClient.getCurrentActionContext()
        val sessionId = BusinessEventsClient.sessionId
        
        // Save crash data as JSON FIRST (before attempting to send)
        val crashData = JSONObject().apply {
            put("crash.class", throwable.javaClass.simpleName)
            put("crash.stackTrace", stackTrace)
            put("action.error", description ?: "unknown")
            put("parentActionId", actionContext?.id?.toString())
            put("sessionId", sessionId)
        }
        
        val crashFile = File(context.filesDir, "crash_report.json")
        try {
            crashFile.writeText(crashData.toString())
            Log.i("PaymentCrashHandler", "💾 Crash data saved to disk")
        } catch (e: Exception) {
            Log.e("PaymentCrashHandler", "Failed to save crash data: ${e.message}")
        }
        
        var crashSentSuccessfully = false
        
        // If there's an open action, finish it with CRASH status first
        actionContext?.let { ctx ->
            try {
                Log.i("PaymentCrashHandler", "🔴 Finishing open action '${ctx.name}' with CRASH status...")
                runBlocking {
                    BusinessEventsClient.endAction(
                        actionId = ctx.id,
                        status = "CRASH",
                        error = description
                    )
                }
                Log.i("PaymentCrashHandler", "✅ Open action finished with CRASH status")
            } catch (e: Exception) {
                Log.e("PaymentCrashHandler", "❌ Failed to finish open action: ${e.message}")
            }
        }
        
        // Now send the crash report
        val parentActionId = actionContext?.id
        val extraAttributes = mapOf(
            "crash.class" to throwable.javaClass.simpleName,
            "crash.stackTrace" to stackTrace,
            "device" to android.os.Build.MODEL
        )
        
        try {
            Log.i("PaymentCrashHandler", "🔴 Sending crash report...")
            runBlocking {
                BusinessEventsClient.sendCrashReport(
                    parentActionId = parentActionId,
                    sessionId = sessionId,
                    error = description,
                    extraAttributes = extraAttributes
                )
            }
            Log.i("PaymentCrashHandler", "✅ Crash report sent successfully")
            crashSentSuccessfully = true
        } catch (e: Exception) {
            Log.e("PaymentCrashHandler", "❌ Failed to send crash report: ${e.message}")
        }
        
        // Delete saved report only if we successfully sent it
        if (crashSentSuccessfully) {
            crashFile.delete()
            Log.i("PaymentCrashHandler", "✅ Saved crash report deleted after successful send")
        } else {
            Log.w("PaymentCrashHandler", "⚠️ Crash report saved to disk for next reboot")
        }

        // Call the original handler to ensure other crash reporters work
        originalHandler?.uncaughtException(thread, throwable)
            ?: exitProcess(1)
    }
}