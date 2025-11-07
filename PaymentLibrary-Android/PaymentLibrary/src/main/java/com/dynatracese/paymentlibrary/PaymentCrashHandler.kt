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
class PaymentCrashHandler(private val context: Context, private val originalHandler: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {

    companion object {
        private var instance: PaymentCrashHandler? = null

        fun register(context: Context) {
            val originalHandler = Thread.getDefaultUncaughtExceptionHandler()
            if (originalHandler !is PaymentCrashHandler) {
                instance = PaymentCrashHandler(context, originalHandler)
                Thread.setDefaultUncaughtExceptionHandler(instance)
                Log.i("registered status", "register: registered successfully")
            }
        }

        fun reportCrash(throwable: Throwable) {
            val sw = StringWriter()
            val pw = PrintWriter(sw)
            throwable.printStackTrace(pw)
            val stackTrace = sw.toString()
            val description = throwable.message
            val extraAttributes = mapOf(
                "crash.class" to throwable.javaClass.simpleName,
                "crash.stackTrace" to stackTrace,
                "device" to android.os.Build.MODEL
            )
            // Get current action context for parentActionId and sessionId
            val actionContext = BusinessEventsClient.getCurrentActionContext()
            val parentActionId = actionContext?.parentActionId
            val sessionId = BusinessEventsClient.sessionId
            
            // Use runBlocking to ensure crash report is sent before app terminates
            try {
                runBlocking {
                    BusinessEventsClient.sendCrashReport(
                        parentActionId = parentActionId,
                        sessionId = sessionId,
                        error = description,
                        extraAttributes = extraAttributes
                    )
                }
                Log.i("PaymentCrashHandler", "Crash report sent successfully")
            } catch (e: Exception) {
                Log.e("PaymentCrashHandler", "Failed to send crash report: ${e.message}", e)
            }
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        Log.i("PaymentCrashHandler", "Uncaught exception occurred: ${throwable.javaClass.simpleName}")
        
        // 1. Send crash report to Dynatrace (blocking operation)
        reportCrash(throwable)
        
        // 2. Collect and serialize crash data for file storage
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        throwable.printStackTrace(pw)
        val stackTrace = sw.toString()
        val description = throwable.message
        
        val crashInfo = "Timestamp: ${Date()}\n" +
                "Device: ${android.os.Build.MODEL}\n" +
                "Exception Class: ${throwable.javaClass.simpleName}\n" +
                "Description: $description\n" +
                "Stack Trace:\n$stackTrace"

        // 3. Write to a file
        try {
            val filename = "payment_crash_report_${System.currentTimeMillis()}.log"
            val file = File(context.filesDir, filename)
            FileOutputStream(file).use {
                it.write(crashInfo.toByteArray())
            }
            Log.d("PaymentCrashHandler", "Crash report saved to ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e("PaymentCrashHandler", "Failed to save crash report", e)
        }

        // 4. Call the original handler to ensure other crash reporters work
        originalHandler?.uncaughtException(thread, throwable)
            ?: exitProcess(1)
    }
}