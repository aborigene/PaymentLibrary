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

object BusinessEventsClient {

    sealed class Auth {
        data class ApiToken(val token: String) : Auth() // "Authorization: Api-Token <token>"
        data class Bearer(val token: String) : Auth()   // "Authorization: Bearer <token>"
    }

    // Session management
    private var hasSessionStarted = false
    val sessionId: String = UUID.randomUUID().toString() // Exposed for crash reporting
    private var sessionActionId: UUID? = null

    // --- FIX: Restored deviceMetadata field ---
    data class Config(
        val endpoint: String,                   // .../api/v2/bizevents/ingest
        val auth: Auth,
        val eventProvider: String,              // maps to CloudEvents `source` (→ event.provider)
        val appVersion: String? = null,         // optional meta
        val deviceInfo: String? = null,         // optional meta
        val deviceMetadata: DeviceMetadataCollector.DeviceMetadata? = null, // comprehensive device metadata
        val maxRetryAttempts: Int = 3           // configurable retry count
    )

    data class BeginOptions(
        val name: String,
        val attributes: Map<String, Any> = emptyMap(),
        val parentActionId: UUID? = null
    )

    // Configure before use
    fun configure(config: Config) {
        this.config = config

        // --- FIX: Restored logging block ---
        config.deviceMetadata?.let { metadata ->
            Log.d("BusinessEventsClient", "Device Metadata Collected:")
            Log.d("BusinessEventsClient", "OS: Android ${metadata.osVersion} (API ${metadata.osVersionCode})")
            Log.d("BusinessEventsClient", "Device: ${metadata.deviceManufacturer} ${metadata.deviceModel}")
            Log.d("BusinessEventsClient", "Network: ${metadata.networkType} - ISP: ${metadata.ispName}")
            Log.d("BusinessEventsClient", "IP Address: ${metadata.deviceIpAddress}")
        }
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
        )

        configure(config)
        Log.i("BusinessEventsClient", "Configured using Secrets.kt for tenant: ${Secrets.dynatraceTenant}")
    }


    // Start an action; returns actionId you will use to end it
    fun beginAction(opts: BeginOptions): UUID {
        val cfg = config ?: run {
            // Use assert instead of Log.e to match iOS behavior
            Log.e("BusinessEventsClient", "BusinessEventsClient not configured. Call configure() first.")
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
            eventType = "custom.rum.sdk.action" // Always use fixed event type
        )
        store.insert(ctx)
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
        val ctx = store.remove(actionId) ?: throw ClientError.UnknownAction

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
        val eventProvider = if (cfg.eventProvider.isBlank()) "Custom RUM Application" else cfg.eventProvider

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
            Log.d("BusinessEventsClient", "CloudEvent JSON: $eventJson")
        } catch (e: Exception) {
            Log.e("BusinessEventsClient", "Failed to serialize CloudEvent: ${e.message}")
        }
        send(event, cfg)
        Log.d("BusinessEventsClient", "Executo end action")
    }

    // Convenience wrapper that auto-finalizes
    suspend fun <T> withAction(
        name: String,
        attributes: Map<String, Any> = emptyMap(),
        parentActionId: UUID? = null,
        body: suspend () -> T
    ): T {
        val id = beginAction(BeginOptions(name, attributes, parentActionId))
        try {
            val result = body()
            endAction(id, status = "SUCCESS")
            Log.d("BusinessEventsClient", "Action name: $name")
            return result
        } catch (e: Exception) {
            // Avoid re-throwing cancellation exceptions, let them propagate
            if (e is CancellationException) throw e
            try {
                endAction(id, status = "FAILURE", error = e.message ?: e.toString())
            } catch (endActionError: Exception) {
                Log.e("BusinessEventsClient", "Failed to send error event: $endActionError")
            }
            throw e
        }
    }

    /**
     * Returns the current action context if available (for crash reporting).
     */
    fun getCurrentActionContext(): ActionContext? {
        return store.getLastActionContext()
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
        data["action.starttime"] = JsonPrimitive(now.time)
        parentActionId?.let { data["action.parentId"] = JsonPrimitive(it.toString()) }
        sessionId?.let { data["session.id"] = JsonPrimitive(it) }
        error?.let { data["action.error"] = JsonPrimitive(it) }
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
        val eventProvider = if (cfg.eventProvider.isBlank()) "Custom RUM Application" else cfg.eventProvider
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
        val eventType: String
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
        Log.w("BusinessEventsClient-sendBusinessEventToDynatrace", "CloudEvent JSON: $eventJson")
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
                    Log.w("BusinessEventsClient", "Send failed (Attempt ${attempt + 1} of ${config.maxRetryAttempts}, Status ${response.code}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                    delay((delaySeconds * 1000).toLong())
                    continue
                } else {
                    // Non-retriable error
                    Log.e("BusinessEventsClient", "Send failed permanently (Status ${response.code}): $responseString")
                    throw ClientError.BadResponse(response.code, responseString)
                }
            } catch (error: Exception) {
                if (attempt == config.maxRetryAttempts - 1) {
                    Log.e("BusinessEventsClient", "Send failed permanently (Network error) after ${config.maxRetryAttempts} attempts: $error")
                    throw ClientError.BadResponse(0, error.message)
                }
                val delaySeconds = initialRetryDelaySeconds * Math.pow(2.0, attempt.toDouble())
                Log.w("BusinessEventsClient", "Send failed (Attempt ${attempt + 1} of ${config.maxRetryAttempts}, Network Error: ${error.message}). Retrying in ${"%.1f".format(delaySeconds)} seconds...")
                delay((delaySeconds * 1000).toLong())
            }
        }
        throw ClientError.BadResponse(0, "Exited retry loop unexpectedly.")
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
    fun insert(ctx: BusinessEventsClient.ActionContext) { dict[ctx.id] = ctx }
    fun lookup(id: UUID): BusinessEventsClient.ActionContext? = dict[id]
    fun remove(id: UUID): BusinessEventsClient.ActionContext? = dict.remove(id)
    fun getLastActionContext(): BusinessEventsClient.ActionContext? = dict.values.lastOrNull()
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