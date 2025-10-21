package com.dynatracese.paymentlibrary

import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.math.pow

// MARK: - Dynatrace Log Event Structure

/**
 * Helper structure to represent a single log line ready for JSON encoding to the Dynatrace API.
 */
data class DynatraceLogEvent(
    val timestamp: Long,
    val level: String,
    val message: String,
    
    // Dynatrace-specific fields for enrichment
    val dtSource: String,
    val logSource: String,
    
    // Contextual log data provided by Log4j2
    val thread: String,
    val logger: String,
    val file: String? = null,
    val function: String? = null,
    val line: Int? = null
) {
    // Custom field names for Gson serialization to match Dynatrace requirements
    fun toMap(): Map<String, Any?> = mapOf(
        "timestamp" to timestamp,
        "level" to level,
        "message" to message,
        "dt.source" to dtSource,
        "log.source" to logSource,
        "thread" to thread,
        "logger" to logger,
        "file" to file,
        "function" to function,
        "line" to line
    ).filterValues { it != null }
}

// MARK: - Dynatrace Logger

/**
 * A custom Android logger that sends logs as JSON payload to the Dynatrace Log Ingest API.
 * Similar to SwiftyBeaver Dynatrace destination on iOS.
 */
object DynatraceLogger {

    enum class LogLevel(val value: String) {
        VERBOSE("VERBOSE"),
        DEBUG("DEBUG"),
        INFO("INFO"),
        WARNING("WARNING"),
        ERROR("ERROR"),
        CRITICAL("CRITICAL")
    }

    // Configuration for the Logger
    private var dtEndpoint: String? = null
    private var dtApiToken: String? = null
    private var applicationName: String? = null
    
    // Configuration for the Retry Mechanism (Exponential Backoff)
    private val maxRetryAttempts = 3
    private val initialRetryDelaySeconds: Double = 2.0 // Initial delay: 2s (will double on subsequent retries)
    
    private val httpClient = OkHttpClient()
    private val gson = Gson()

    /**
     * Configure the Dynatrace logger with necessary settings.
     */
    fun configure(endpoint: String, apiToken: String, appName: String) {
        this.dtEndpoint = endpoint
        this.dtApiToken = apiToken
        this.applicationName = appName
        Log.i("DynatraceLogger", "DynatraceLogger configured successfully")
    }

    /**
     * Log a message to Dynatrace at the specified level
     */
    @OptIn(DelicateCoroutinesApi::class)
    fun log(level: LogLevel, message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) {
        // Also log to Android Log (catch exceptions in case we're in unit test environment)
        try {
            when (level) {
                LogLevel.VERBOSE -> Log.v(tag, message, throwable)
                LogLevel.DEBUG -> Log.d(tag, message, throwable)
                LogLevel.INFO -> Log.i(tag, message, throwable)
                LogLevel.WARNING -> Log.w(tag, message, throwable)
                LogLevel.ERROR -> Log.e(tag, message, throwable)
                LogLevel.CRITICAL -> Log.wtf(tag, message, throwable)
            }
        } catch (e: Exception) {
            // In unit test environment, Android Log might not be available
            // Fall back to println
            println("$level/$tag: $message")
            if (throwable != null) {
                throwable.printStackTrace()
            }
        }

        // Check if configured
        val endpoint = dtEndpoint
        val token = dtApiToken
        val appName = applicationName
        
        if (endpoint == null || token == null || appName == null) {
            Log.w("DynatraceLogger", "DynatraceLogger not configured, skipping remote logging")
            return
        }

        // 1. Create the log event payload
        val logEvent = DynatraceLogEvent(
            timestamp = System.currentTimeMillis(),
            level = level.value,
            message = message,
            dtSource = appName,
            logSource = "AndroidLogger",
            thread = Thread.currentThread().name,
            logger = tag,
            file = null, // Android doesn't easily provide this
            function = null, // Android doesn't easily provide this
            line = null // Android doesn't easily provide this
        )
        
        // 2. Execute the asynchronous HTTP call in a detached coroutine
        GlobalScope.launch(Dispatchers.IO) {
            try {
                // The Dynatrace Log API expects an array of log lines
                sendLogToDynatrace(listOf(logEvent))
            } catch (error: Exception) {
                // Log the final failure internally after all retries have been exhausted
                Log.e("DynatraceLogger", "Failed to send log to Dynatrace after $maxRetryAttempts attempts: $error")
            }
        }
    }

    // Convenience methods for different log levels
    fun verbose(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.VERBOSE, message, tag, throwable)
    fun debug(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.DEBUG, message, tag, throwable)
    fun info(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.INFO, message, tag, throwable)
    fun warning(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.WARNING, message, tag, throwable)
    fun error(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.ERROR, message, tag, throwable)
    fun critical(message: String, tag: String = "PaymentLibrary", throwable: Throwable? = null) = log(LogLevel.CRITICAL, message, tag, throwable)

    /**
     * Performs the HTTP POST request to the Dynatrace Log Ingest API with exponential backoff retries.
     */
    private suspend fun sendLogToDynatrace(events: List<DynatraceLogEvent>) {
        val endpoint = dtEndpoint ?: return
        val token = dtApiToken ?: return
        
        // --- Prepare static request properties (same for all retries) ---
        val mediaType = "application/json; charset=utf-8".toMediaType()
        val jsonBody = gson.toJson(events.map { it.toMap() })
        val requestBody = jsonBody.toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url(endpoint)
            .post(requestBody)
            .header("Content-Type", "application/json; charset=utf-8")
            .header("Authorization", "Api-Token $token")
            .build()

        // --- Retry Loop ---
        for (attempt in 0 until maxRetryAttempts) {
            try {
                val response = httpClient.newCall(request).execute()
                
                if (response.code == 204) {
                    return // Success!
                }
                
                val responseString = response.body?.string() ?: "No error message provided"
                
                // Determine if the server response is retriable (5xx or 429) or permanent (other 4xx)
                val error: DynatraceError = when {
                    response.code >= 500 || response.code == 429 -> {
                        // 5xx (Server Error) and 429 (Too Many Requests) are temporary and retriable
                        DynatraceError.ServerError(response.code, responseString)
                    }
                    else -> {
                        // Other 4xx errors (400, 401, 403, etc.) are permanent and non-retriable
                        DynatraceError.NonRetriableError(response.code, responseString)
                    }
                }
                
                if (!error.isRetriable || attempt == maxRetryAttempts - 1) {
                    // Final failure or a permanent (4xx excluding 429) error, throw immediately/after last attempt
                    println("Dynatrace send failed permanently (Status ${response.code}): $responseString")
                    throw error
                }
                
                // Retriable error (5xx or 429), pause and retry
                val delaySeconds = initialRetryDelaySeconds * 2.0.pow(attempt.toDouble())
                println("Dynatrace send failed (Attempt ${attempt + 1} of $maxRetryAttempts, Status ${response.code}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                delay((delaySeconds * 1000).toLong())

            } catch (error: Exception) {
                // Catch network-level errors (like timeouts, no connectivity)
                
                if (attempt == maxRetryAttempts - 1) {
                    println("Dynatrace send failed permanently (Network error) after $maxRetryAttempts attempts: $error")
                    throw DynatraceError.NetworkError(error)
                }
                
                // Pause and retry for network errors
                val delaySeconds = initialRetryDelaySeconds * 2.0.pow(attempt.toDouble())
                println("Dynatrace send failed (Attempt ${attempt + 1} of $maxRetryAttempts, Network Error: ${error.message}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                delay((delaySeconds * 1000).toLong())
            }
        }
        // This line should technically be unreachable, but is included for completeness
        throw DynatraceError.ServerError(0, "Exited retry loop unexpectedly.")
    }
}

// MARK: - Custom Error Types

sealed class DynatraceError : Exception() {
    data object InvalidURLEndpoint : DynatraceError()
    data object InvalidResponse : DynatraceError()
    data class ServerError(val statusCode: Int, val body: String) : DynatraceError()
    data class NonRetriableError(val statusCode: Int, val body: String) : DynatraceError()
    data class NetworkError(override val cause: Exception) : DynatraceError()
    
    /**
     * Determines if the error is temporary (e.g., 5xx server error, 429 rate limit, network timeout) and should be retried.
     */
    val isRetriable: Boolean
        get() = when (this) {
            is ServerError, is NetworkError, is InvalidResponse -> {
                // 5xx errors, 429 (handled upstream in sendLogToDynatrace), network failure, or bad/non-HTTP response are retriable
                true
            }
            is InvalidURLEndpoint, is NonRetriableError -> {
                // Invalid URL or non-retriable 4xx errors are not retriable
                false
            }
        }
}