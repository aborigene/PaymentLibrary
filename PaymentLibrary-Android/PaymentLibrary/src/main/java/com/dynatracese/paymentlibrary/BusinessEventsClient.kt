// BusinessEventsClient.kt
// Dynatrace Business Events (bizevents/ingest) client for Android (Kotlin)
// - Singleton with beginAction / endAction
// - Sends CloudEvents to /api/v2/bizevents/ingest when an action finishes
// - Supports parent/child cascades via action.id and action.parentId correlation
//
// Requirements:
//  - Create an API token with scope `bizevents.ingest` OR use OAuth Bearer.
//  - Endpoint (classic env): https://{env}.live.dynatrace.com/api/v2/bizevents/ingest
//  - Content-Type (CloudEvents): application/cloudevent+json
//
// Notes:
//  - We include explicit action fields (action.id, action.parentId, duration) for analyzing cascades.
//
//  - If you prefer pure JSON instead of CloudEvents, switch the encoder at the bottom.

package com.dynatracese.paymentlibrary

import android.content.Context
import android.os.Build
import android.util.Log
// No import needed for DeviceMetadataCollector as it's in the same package
import com.dynatracese.paymentlibrary.Secrets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.coroutineContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException

// MARK: - Public API

// Coroutine context key for tracking current action ID
private data class CurrentActionKey(val actionId: UUID) : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<CurrentActionKey>
    override val key: CoroutineContext.Key<*> get() = Key
}

object BusinessEventsClient {

    enum class LogLevel {
        VERBOSE, DEBUG, INFO, WARN, ERROR, NONE
    }

    sealed class Auth {
        data class ApiToken(val token: String) : Auth() // "Authorization: Api-Token <token>"
        data class Bearer(val token: String) : Auth()   // "Authorization: Bearer <token>"
    }

    // Session management
    private var hasSessionStarted = false
    val sessionId: String = UUID.randomUUID().toString() // Exposed for crash reporting
    private var sessionActionId: UUID? = null

    // Log level configuration - defaults to INFO
    private var logLevel: LogLevel = LogLevel.INFO

    // --- FIX: Restored deviceMetadata field ---
    data class Config(
        val endpoint: String,                   // .../api/v2/bizevents/ingest
        val auth: Auth,
        val eventProvider: String,              // maps to CloudEvents `source` (→ event.provider)
        val appVersion: String? = null,         // optional meta
        val deviceInfo: String? = null,         // optional meta
        val deviceMetadata: DeviceMetadataCollector.DeviceMetadata? = null, // comprehensive device metadata
        val maxRetryAttempts: Int = 3,          // configurable retry count
        val actionTimeoutSeconds: Long = 7,     // timeout in seconds before auto-finishing actions
        val logLevel: LogLevel = LogLevel.INFO  // default log level
    )

    data class BeginOptions(
        val name: String,
        val attributes: Map<String, Any> = emptyMap(),
        val parentActionId: UUID? = null
    )

    // Helper methods for logging with level check
    private fun logV(tag: String, message: String) {
        if (logLevel.ordinal <= LogLevel.VERBOSE.ordinal) Log.v(tag, message)
    }

    private fun logD(tag: String, message: String) {
        if (logLevel.ordinal <= LogLevel.DEBUG.ordinal) Log.d(tag, message)
    }

    private fun logI(tag: String, message: String) {
        if (logLevel.ordinal <= LogLevel.INFO.ordinal) Log.i(tag, message)
    }

    private fun logW(tag: String, message: String) {
        if (logLevel.ordinal <= LogLevel.WARN.ordinal) Log.w(tag, message)
    }

    private fun logE(tag: String, message: String) {
        if (logLevel.ordinal <= LogLevel.ERROR.ordinal) Log.e(tag, message)
    }

    // Configure before use
    fun configure(config: Config) {
        this.config = config
        this.logLevel = config.logLevel

        // --- FIX: Restored logging block ---
        config.deviceMetadata?.let { metadata ->
            logD("BusinessEventsClient", "Device Metadata Collected:")
            logD("BusinessEventsClient", "OS: Android ${metadata.osVersion} (API ${metadata.osVersionCode})")
            logD("BusinessEventsClient", "Device: ${metadata.deviceManufacturer} ${metadata.deviceModel}")
            logD("BusinessEventsClient", "Network: ${metadata.networkType} - ISP: ${metadata.ispName}")
            logD("BusinessEventsClient", "IP Address: ${metadata.deviceIpAddress}")
        }
        
        // Automatically create session_started event on first configuration
        if (!hasSessionStarted) {
            createSessionStartedEvent()
        }

        logI("BusinessEventsClient", "Configured with log level: ${config.logLevel}")
    }

    /**
     * Enhanced configuration method that automatically collects device metadata
     * @param context Android context needed for device information collection
     * @param endpoint Dynatrace bizevents ingest endpoint
     * @param auth Authentication method (API token or Bearer token)
     * @param eventProvider Event provider identifier
     * @param defaultEventType Default event type for business events
     * @param appVersion Application version (optional)
     */
    fun configureWithDeviceMetadata(
        context: Context,
        endpoint: String,
        auth: Auth,
        eventProvider: String,
        appVersion: String? = null
    ) {
        // --- FIX: Use DeviceMetadataCollector as intended ---
        val deviceMetadata = DeviceMetadataCollector.collectMetadata(context)
        val deviceInfo = DeviceMetadataCollector.formatDeviceInfo(deviceMetadata)

        val config = Config(
            endpoint = endpoint,
            auth = auth,
            eventProvider = eventProvider,
            appVersion = appVersion,
            deviceInfo = deviceInfo,
            deviceMetadata = deviceMetadata
            // logLevel uses default from Config (INFO)
        )

        configure(config)
    }

    /**
     * Enhanced configuration method that automatically collects device metadata
     * and reads Dynatrace credentials from the Secrets.kt file.
     *
     * @param context Android context needed for device information collection
     * @param eventProvider Event provider identifier
     * @param defaultEventType Default event type for business events
     * @param appVersion Application version (optional)
     */
    fun configureFromSecrets(
        context: Context,
        eventProvider: String,
        appVersion: String? = null
    ) {
        // --- FIX: Use DeviceMetadataCollector as intended ---
        val deviceMetadata = DeviceMetadataCollector.collectMetadata(context)
        val deviceInfo = DeviceMetadataCollector.formatDeviceInfo(deviceMetadata)

        // Read endpoint and auth from Secrets.kt
        val endpoint = "${Secrets.dynatraceTenant}/api/v2/bizevents/ingest"
        val auth = Auth.ApiToken(Secrets.dynatraceBusinessEventIngestToken)

        val config = Config(
            endpoint = endpoint,
            auth = auth,
            eventProvider = eventProvider,
            appVersion = appVersion,
            deviceInfo = deviceInfo,
            deviceMetadata = deviceMetadata
            // logLevel uses default from Config (INFO)
        )

        configure(config)
        logI("BusinessEventsClient", "Configured using Secrets.kt for tenant: ${Secrets.dynatraceTenant}")
    }


    // Start an action; returns actionId you will use to end it
    fun beginAction(opts: BeginOptions): UUID {
        val cfg = config ?: run {
            // Use assert instead of logE to match iOS behavior
            logE("BusinessEventsClient", "BusinessEventsClient not configured. Call configure() first.")
            return UUID.randomUUID()
        }
        val now = Date()

        // Determine effective parent ID: explicit > session action for first-level actions
        val effectiveParentId = opts.parentActionId ?: (if (opts.name == "session_started") null else sessionActionId)

        val ctx = ActionContext(
            id = UUID.randomUUID(),
            name = opts.name,
            startedAt = now,
            attributes = opts.attributes.toJsonElementMap(),
            parentActionId = effectiveParentId,
            eventType = "custom.rum.sdk.action", // Always use fixed event type
            timeoutJob = null
        )
        
        // Schedule timeout job
        val timeoutJob = GlobalScope.launch {
            delay(cfg.actionTimeoutSeconds * 1000)
            try {
                // Clear the timeout job reference BEFORE calling endAction to prevent self-cancellation
                // This ensures the timeout coroutine can complete sending the event
                val actionCtx = store.lookup(ctx.id)
                if (actionCtx != null) {
                    actionCtx.timeoutJob = null
                }
                
                endAction(
                    ctx.id,
                    status = "TIMEOUT",
                    error = "Action exceeded timeout of ${cfg.actionTimeoutSeconds}s"
                )
                logI("BusinessEventsClient", "Action '${ctx.name}' auto-finished with TIMEOUT status")
            } catch (e: ClientError.UnknownAction) {
                // Action was already finished by user code - this is expected and not an error
                logD("BusinessEventsClient", "Action '${ctx.name}' was already finished when timeout fired")
            } catch (e: Exception) {
                logE("BusinessEventsClient", "Failed to auto-finish timed out action '${ctx.name}': ${e.message}")
            }
        }
        ctx.timeoutJob = timeoutJob
        
        store.insert(ctx)
        logD("BusinessEventsClient", "Action '${ctx.name}' started, timeout: ${cfg.actionTimeoutSeconds}s")
        return ctx.id
    }

    // Finish and send immediately
    suspend fun endAction(
        actionId: UUID,
        status: String = "SUCCESS",
        error: String? = null,
        extraAttributes: Map<String, Any> = emptyMap()
    ) {
        val cfg = config ?: throw ClientError.NotConfigured
        val ctx = store.lookup(actionId) ?: throw ClientError.UnknownAction
        
        // Mark action as finished but keep it in store for crash reporting
        if (ctx.finished) {
            logW("BusinessEventsClient", "Action ${ctx.name} already finished, skipping duplicate endAction")
            return
        }
        ctx.finished = true
        
        // Cancel timeout job since action is ending normally
        ctx.timeoutJob?.cancel()
        ctx.timeoutJob = null
        
        // Schedule delayed removal (5 seconds) to allow crash handlers to access the action
        GlobalScope.launch {
            delay(5000)
            store.remove(actionId)
            DynatraceLogger.info("Action ${ctx.name} removed from store after delay", "BusinessEventsClient")
        }

        val finishedAt = Date()
        val durationMs = (finishedAt.time - ctx.startedAt.time)

        // Merge attributes (extra overrides start-level)
        val data = mutableMapOf<String, JsonElement>()
        data.putAll(ctx.attributes)
        data.putAll(extraAttributes.toJsonElementMap())
        data["action.id"] = JsonPrimitive(ctx.id.toString())
        ctx.parentActionId?.let { data["action.parentId"] = JsonPrimitive(it.toString()) }
        data["action.name"] = JsonPrimitive(ctx.name)
        data["action.status"] = JsonPrimitive(status)
        error?.let { data["action.error"] = JsonPrimitive(it) }
        data["action.durationMs"] = JsonPrimitive(durationMs)
        data["action.starttime"] = JsonPrimitive(DateFormatter.dtTime.format(ctx.startedAt))
        data["action.endtime"] = JsonPrimitive(DateFormatter.dtTime.format(finishedAt))
        data["session.id"] = JsonPrimitive(sessionId)  // Add session.id to every action
        config?.appVersion?.let { data["app.version"] = JsonPrimitive(it) }
        config?.deviceInfo?.let { data["device.info"] = JsonPrimitive(it) }

        // --- FIX: Restored block to add all device attributes ---
        config?.deviceMetadata?.let { metadata ->
            val deviceAttributes = DeviceMetadataCollector.toEventAttributes(metadata)
            deviceAttributes.forEach { (key, value) ->
                data[key] = when (value) {
                    is String -> JsonPrimitive(value)
                    is Number -> JsonPrimitive(value)
                    is Boolean -> JsonPrimitive(value)
                    else -> JsonPrimitive(value.toString())
                }
            }
        }

        // Always use fixed event type
        val eventType = "custom.rum.sdk.action"
        // Use provided eventProvider or default
        val eventProvider = if (cfg.eventProvider.isBlank()) "CustomRumSDK" else cfg.eventProvider

        // Use ms Unix Epoch for start/end time
        data["action.starttime"] = JsonPrimitive(ctx.startedAt.time)
        data["action.endtime"] = JsonPrimitive(finishedAt.time)

        val event = CloudEvent(
            specversion = "1.0",
            id = UUID.randomUUID().toString(),
            source = eventProvider,
            type = eventType,
            time = DateFormatter.dtTime.format(finishedAt),
            traceparent = null,
            data = JsonObject(data)
        )

        // Log the event content before sending
        try {
            val eventJson = json.encodeToString(event)
            logD("BusinessEventsClient", "CloudEvent JSON: $eventJson")
        } catch (e: Exception) {
            logE("BusinessEventsClient", "Failed to serialize CloudEvent: ${e.message}")
        }
        
        val sendStartTime = System.currentTimeMillis()
        logD("BusinessEventsClient-endAction", "⏱️ [${ctx.name}] BEFORE send() - timestamp: $sendStartTime")
        
        send(event, cfg)
        
        val sendEndTime = System.currentTimeMillis()
        val sendDuration = sendEndTime - sendStartTime
        logD("BusinessEventsClient-endAction", "⏱️ [${ctx.name}] AFTER send() - timestamp: $sendEndTime, duration: ${sendDuration}ms")
        logD("BusinessEventsClient", "Executo end action")
    }

    // Convenience wrapper that auto-finalizes with automatic parent-child relationship tracking
    suspend fun <T> withAction(
        name: String,
        attributes: Map<String, Any> = emptyMap(),
        parentActionId: UUID? = null,
        body: suspend () -> T
    ): T {
        // Automatically use current action as parent if no explicit parent provided
        val currentActionId = coroutineContext[CurrentActionKey]?.actionId
        val effectiveParentId = parentActionId ?: currentActionId
        
        val id = beginAction(BeginOptions(name, attributes, effectiveParentId))
        
        // Set this action as current in coroutine context for nested actions
        return withContext(CurrentActionKey(id)) {
            try {
                val result = body()
                try {
                    endAction(id, status = "SUCCESS")
                    logD("BusinessEventsClient", "Action name: $name")
                } catch (e: ClientError.UnknownAction) {
                    // Action was already finished by timeout - this is expected
                    logD("BusinessEventsClient", "Action '$name' was already finished (likely by timeout)")
                }
                result
            } catch (e: Exception) {
                // Avoid re-throwing cancellation exceptions, let them propagate
                if (e is CancellationException) throw e
                try {
                    endAction(id, status = "FAILURE", error = e.message ?: e.toString())
                } catch (endActionError: ClientError.UnknownAction) {
                    // Action was already finished by timeout - this is expected
                    logD("BusinessEventsClient", "Action '$name' was already finished when trying to record failure (likely by timeout)")
                } catch (endActionError: Exception) {
                    logE("BusinessEventsClient", "Failed to send error event: $endActionError")
                }
                throw e
            }
        }
    }

    /**
     * Returns the current action context if available (for crash reporting).
     */
    fun getCurrentActionContext(): ActionContext? {
        val context = store.getLastActionContext()
        DynatraceLogger.info(
            "getCurrentActionContext() called - result: ${if (context != null) "actionId=${context.id}" else "null (no active action)"}",
            "BusinessEventsClient"
        )
        return context
    }

    /**
     * Sends a crash report as a business event to Dynatrace.
     * @param parentActionId Optional parent action UUID
     * @param sessionId Session ID string
     * @param error Error message or description
     * @param extraAttributes Additional attributes to include in the event
     */
    suspend fun sendCrashReport(
        parentActionId: UUID?,
        sessionId: String?,
        error: String?,
        extraAttributes: Map<String, Any> = emptyMap()
    ) {
        val cfg = config ?: throw ClientError.NotConfigured
        val now = Date()
        val data = mutableMapOf<String, JsonElement>()
        data["action.id"] = JsonPrimitive(UUID.randomUUID().toString())
        data["action.name"] = JsonPrimitive("crash")
        data["action.status"] = JsonPrimitive("CRASH")
        data["action.starttime"] = JsonPrimitive(now.time)
        parentActionId?.let { data["action.parentId"] = JsonPrimitive(it.toString()) }
        sessionId?.let { data["session.id"] = JsonPrimitive(it) }
        error?.let { data["action.error"] = JsonPrimitive(it) }
        
        // Add mapping file identifiers for deobfuscation
        data["crash.package"] = JsonPrimitive(BuildConfig.LIBRARY_PACKAGE_NAME)
        data["crash.versionCode"] = JsonPrimitive(BuildConfig.VERSION_CODE)
        data["crash.versionName"] = JsonPrimitive(BuildConfig.VERSION_NAME)
        data["crash.platform"] = JsonPrimitive("Android")
        
        data.putAll(extraAttributes.toJsonElementMap())
        cfg.appVersion?.let { data["app.version"] = JsonPrimitive(it) }
        cfg.deviceInfo?.let { data["device.info"] = JsonPrimitive(it) }
        cfg.deviceMetadata?.let { metadata ->
            val deviceAttributes = DeviceMetadataCollector.toEventAttributes(metadata)
            deviceAttributes.forEach { (key, value) ->
                data[key] = when (value) {
                    is String -> JsonPrimitive(value)
                    is Number -> JsonPrimitive(value)
                    is Boolean -> JsonPrimitive(value)
                    else -> JsonPrimitive(value.toString())
                }
            }
        }
        val eventType = "custom.rum.sdk.crash"
        val eventProvider = if (cfg.eventProvider.isBlank()) "CustomRumSDK" else cfg.eventProvider
        val event = CloudEvent(
            specversion = "1.0",
            id = UUID.randomUUID().toString(),
            source = eventProvider,
            type = eventType,
            time = DateFormatter.dtTime.format(now),
            traceparent = null,
            data = JsonObject(data)
        )
        sendBusinessEventToDynatrace(event, cfg)
    }

    // MARK: - Internals

    private var config: Config? = null
    private val store = InMemoryStore()
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    data class ActionContext(
        val id: UUID,
        val name: String,
        val startedAt: Date,
        val attributes: Map<String, JsonElement>,
        val parentActionId: UUID?,
        val eventType: String,
        var timeoutJob: kotlinx.coroutines.Job? = null,
        var finished: Boolean = false  // Track if action has been finished
    )

    sealed class ClientError : Exception() {
        data object NotConfigured : ClientError()
        data object UnknownAction : ClientError()
        data class BadResponse(val code: Int, val body: String?) : ClientError()
    }

    private suspend fun send(event: CloudEvent, config: Config) = sendBusinessEventToDynatrace(event, config)

    private suspend fun sendBusinessEventToDynatrace(event: CloudEvent, config: Config) = withContext(Dispatchers.IO) {
        val mediaType = "application/cloudevent+json".toMediaType()
        val requestBody = json.encodeToString(event).toRequestBody(mediaType)
        val request = Request.Builder()
            .url(config.endpoint)
            .post(requestBody)
            .apply {
                when (config.auth) {
                    is Auth.ApiToken -> header("Authorization", "Api-Token ${config.auth.token}")
                    is Auth.Bearer ->   header("Authorization","Bearer ${config.auth.token}")
                }
            }
            .header("Content-Type", "application/cloudevent+json")
            .build()

        val eventJson = json.encodeToString(event)
        val initialRetryDelaySeconds = 1.0
        for (attempt in 0 until config.maxRetryAttempts) {
            try {
                val response = httpClient.newCall(request).execute()
                
                if (response.code == 202) {
                    return@withContext // Success!
                }
                val responseString = response.body?.string() ?: "No error message provided"
                if (response.code >= 500 || response.code == 429) {
                    // Retriable error
                    val delaySeconds = initialRetryDelaySeconds * Math.pow(2.0, attempt.toDouble())
                    logW("BusinessEventsClient", "⚠️ Send failed (Attempt ${attempt + 1} of ${config.maxRetryAttempts}, Status ${response.code}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                    delay((delaySeconds * 1000).toLong())
                    continue
                } else {
                    // Non-retriable error
                    logE("BusinessEventsClient", "❌ Send failed permanently (Status ${response.code}): $responseString")
                    throw ClientError.BadResponse(response.code, responseString)
                }
            } catch (error: Exception) {
                if (attempt == config.maxRetryAttempts - 1) {
                    logE("BusinessEventsClient", "❌ Send failed permanently (Network error) after ${config.maxRetryAttempts} attempts: $error")
                    throw ClientError.BadResponse(0, error.message)
                }
                val delaySeconds = initialRetryDelaySeconds * Math.pow(2.0, attempt.toDouble())
                logW("BusinessEventsClient", "⚠️ Send failed (Attempt ${attempt + 1} of ${config.maxRetryAttempts}, Network Error: ${error.message}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                delay((delaySeconds * 1000).toLong())
            }
        }
        throw ClientError.BadResponse(0, "Exited retry loop unexpectedly.")
    }
    
    /**
     * Creates a session_started business event with comprehensive device metadata.
     * This is called automatically when BusinessEventsClient is first configured.
     */
    private fun createSessionStartedEvent() {
        val cfg = config ?: run {
            logE("BusinessEventsClient", "❌ Cannot create session_started event: BusinessEventsClient not configured")
            return
        }
        
        // Mark session as started to prevent duplicate events
        hasSessionStarted = true
        
        GlobalScope.launch {
            try {
                // Collect device metadata for session start
                val deviceAttributes = cfg.deviceMetadata?.let { metadata ->
                    DeviceMetadataCollector.toEventAttributes(metadata)
                } ?: emptyMap()
                
                // Add session-specific attributes
                val attributes = deviceAttributes.toMutableMap()
                attributes["session.id"] = sessionId
                attributes["session.start_time"] = DateFormatter.dtTime.format(Date())
                attributes["event.provider"] = cfg.eventProvider
                attributes["session.initialization_type"] = "business_events_configured"
                
                // Begin session_started event - this will become the parent for all first-level actions
                val actionId = beginAction(BeginOptions(
                    name = "session_started",
                    attributes = attributes
                ))
                
                // Store session action ID to use as default parent for first-level actions
                sessionActionId = actionId
                
                // End session_started event immediately
                endAction(
                    actionId,
                    status = "SUCCESS",
                    extraAttributes = mapOf(
                        "session.duration_ms" to 0,
                        "session.components_initialized" to listOf(
                            "BusinessEventsClient",
                            "DeviceMetadataCollector"
                        )
                    )
                )
                
            } catch (e: Exception) {
                logE("BusinessEventsClient", "❌ Failed to create session_started event: ${e.message}")
            }
        }
    }
}

// MARK: - CloudEvents payload

@Serializable
data class CloudEvent(
    val specversion: String,
    val id: String,
    val source: String,
    val type: String,
    val time: String,
    val traceparent: String?,  // Not used - correlation via action.id instead
    val data: JsonObject
)

// MARK: - In-memory store (thread-safe)

private class InMemoryStore {
    private val dict = ConcurrentHashMap<UUID, BusinessEventsClient.ActionContext>()
    private val lastActionId = java.util.concurrent.atomic.AtomicReference<UUID?>(null)
    
    fun insert(ctx: BusinessEventsClient.ActionContext) { 
        dict[ctx.id] = ctx 
        lastActionId.set(ctx.id)
        DynatraceLogger.info("Action inserted: ${ctx.id}, active actions: ${dict.size}", "InMemoryStore")
    }
    
    fun lookup(id: UUID): BusinessEventsClient.ActionContext? = dict[id]
    
    fun remove(id: UUID): BusinessEventsClient.ActionContext? {
        val ctx = dict.remove(id)
        ctx?.timeoutJob?.cancel()
        
        // Update lastActionId if we removed the last one
        if (lastActionId.get() == id) {
            lastActionId.set(dict.keys.firstOrNull())
        }
        return ctx
    }
    
    fun getLastActionContext(): BusinessEventsClient.ActionContext? {
        val actionId = lastActionId.get()
        DynatraceLogger.info(
            "getLastActionContext() - lastActionId=${actionId}, dict.size=${dict.size}, keys=${dict.keys.joinToString()}",
            " "
        )
        if (actionId == null) return null
        return dict[actionId]
    }
}

// MARK: - Helpers

private fun Map<String, Any>.toJsonElementMap(): Map<String, JsonElement> {
    return this.mapValues { (_, value) ->
        when (value) {
            is String -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            is Boolean -> JsonPrimitive(value)
            else -> JsonPrimitive(value.toString())
        }
    }
}

private object DateFormatter {
    val dtTime: SimpleDateFormat by lazy {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }
}

// MARK: - Example Usage
/*
// In your Application class or an initializer
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // This example shows the *old* way
        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = "https://YOUR_ENV.live.dynatrace.com/api/v2/bizevents/ingest",
                auth = BusinessEventsClient.Auth.ApiToken("dt0c01.abc123......"),
                eventProvider = "com.unitedgames.payment.android",
                defaultEventType = "com.unitedgames.user.action",
                appVersion = BuildConfig.VERSION_NAME,
                deviceInfo = "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
                deviceMetadata = null // Old way didn't have this
            )
        )

        // The *new* way (as used in PaymentClient) would be:
        // BusinessEventsClient.configureFromSecrets(
        //     context = this,
        //     eventProvider = "com.unitedgames.payment.android",
        //     defaultEventType = "com.unitedgames.user.action",
        //     appVersion = BuildConfig.VERSION_NAME
        // )
    }
}


// Somewhere in your app (e.g., a ViewModel)
// Remember to launch coroutines from a CoroutineScope (like viewModelScope)
fun performCheckout() {
    viewModelScope.launch {
        val parent = BusinessEventsClient.beginAction(BusinessEventsClient.BeginOptions(name = "Checkout"))
        val child = BusinessEventsClient.beginAction(BusinessEventsClient.BeginOptions(name = "AddCard", parentActionId = parent))

        // do some work...

        BusinessEventsClient.endAction(child, status = "OK")
        BusinessEventsClient.endAction(parent, status = "OK")
    }
}
*/