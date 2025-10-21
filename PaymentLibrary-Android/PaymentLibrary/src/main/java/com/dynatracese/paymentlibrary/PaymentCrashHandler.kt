package com.dynatracese.paymentlibrary

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.util.*
import kotlin.system.exitProcess
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
            
            // Log crash using DynatraceLogger (which sends to Dynatrace Log Ingest API)
            DynatraceLogger.error("Crash reported - Class: ${throwable.javaClass.simpleName}, Description: $description, StackTrace: $stackTrace", "PaymentCrashHandler", throwable)
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        // 1. Collect and serialize crash data
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        throwable.printStackTrace(pw)
        val stackTrace = sw.toString()
        val description = throwable.message
        
        Log.i("PaymentCrashHandler", "Uncaught exception occurred")
        
        // Report crash using the new method
        reportCrash(throwable)

        val crashInfo = "Timestamp: ${Date()}\n" +
                "Device: ${android.os.Build.MODEL}\n" +
                "Exception Class: ${throwable.javaClass.simpleName}\n" +
                "Description: $description\n" +
                "Stack Trace:\n$stackTrace"

        // 2. Write to a file
        try {
            val filename = "payment_crash_report_${System.currentTimeMillis()}.log"
            val file = File(context.filesDir, filename)
            FileOutputStream(file).use {
                it.write(crashInfo.toByteArray())
            }
            Log.d("PaymentLibrary", "Crash report saved to ${file.absolutePath}")
        } catch (e: Exception) {
            Log.e("PaymentLibrary", "Failed to save crash report", e)
        }

        // 3. Call the original handler to ensure other crash reporters work
        originalHandler?.uncaughtException(thread, throwable)
            ?: exitProcess(1)
    }
}