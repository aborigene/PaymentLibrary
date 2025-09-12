package com.dynatracese.paymentlibrary

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.PrintWriter
import java.io.StringWriter
import java.util.*
import kotlin.system.exitProcess
import com.dynatrace.openkit.DynatraceOpenKitBuilder
import com.dynatrace.openkit.api.OpenKit
import com.dynatrace.openkit.api.Session
import com.dynatrace.openkit.api.Action

class PaymentCrashHandler(private val context: Context, private val originalHandler: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {

    companion object {
        private lateinit var crashSession: Session

        fun register(context: Context, session: Session) {
            crashSession = session
            val originalHandler = Thread.getDefaultUncaughtExceptionHandler()
            if (originalHandler !is PaymentCrashHandler) {
                Thread.setDefaultUncaughtExceptionHandler(PaymentCrashHandler(context, originalHandler))
                Log.i("registered status", "register: registered successfully")
            }
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        // 1. Collect and serialize crash data
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        throwable.printStackTrace(pw)
        val stackTrace = sw.toString()
        val description = throwable.message
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")
        Log.i("test","uncaughtException: This is a log from the PaymentCrashHandler....")


//        PaymentCrashHandler.crashSession.reportCrash(throwable.message, "Deu ruim", stackTrace)
        crashSession.reportCrash(throwable.javaClass.simpleName, description, stackTrace)
        Thread.sleep(2000)
        Log.i("OpenKit", "class: "+throwable.javaClass.simpleName)
        Log.i("OpenKit", "description: "+description)
        Log.i("OpenKit", "stacktrace: "+stackTrace)
        Log.i("Crash", "This the sent crash session info:"+ crashSession.toString())

        val crashInfo = "Timestamp: ${Date()}\n" +
                "Device: ${android.os.Build.MODEL}\n" +
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