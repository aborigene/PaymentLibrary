// BusinessEventsClient.kt
// Dynatrace Business Events (bizevents/ingest) client for Android (Kotlin)
// - Singleton with beginAction / endAction
// - Sends CloudEvents to /api/v2/bizevents/ingest when an action finishes
// - Supports parent/child cascades via W3C traceparent (same trace-id, parent span)
//
// Requirements:
//  - Create an API token with scope `bizevents.ingest` OR use OAuth Bearer.
//  - Endpoint (classic env): https://{env}.live.dynatrace.com/api/v2/bizevents/ingest
//  - Content-Type (CloudEvents): application/cloudevent+json
//
// Notes:
//  - We include both explicit action fields (action.id, action.parentId, duration) and a
//    proper traceparent so you can analyze cascades by either approach.
//
//  - If you prefer pure JSON instead of CloudEvents, switch the encoder at the bottom.

package com.dynatracese.paymentlibrary

import android.os.Build
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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

    data class Config(
        val endpoint: String,                   // .../api/v2/bizevents/ingest
        val auth: Auth,
        val eventProvider: String,              // maps to CloudEvents `source` (→ event.provider)
        val defaultEventType: String,           // e.g. "com.unitedgames.user.action"
        val appVersion: String? = null,         // optional meta
        val deviceInfo: String? = null          // optional meta
    )

    data class BeginOptions(
        val name: String,
        val attributes: Map<String, Any> = emptyMap(),
        val parentActionId: UUID? = null
    )

    // Configure before use
    fun configure(config: Config) {
        this.config = config
    }

    // Start an action; returns actionId you will use to end it
    fun beginAction(opts: BeginOptions): UUID {
        val cfg = config ?: run {
            // Use assert instead of Log.e to match iOS behavior
            Log.e("BusinessEventsClient", "BusinessEventsClient not configured. Call configure() first.")
            return UUID.randomUUID()
        }
        val now = Date()
        // If parent exists, re-use its traceId, otherwise create a new one
        var traceId = randomTraceId()
        var parentSpan: String? = null
        if (opts.parentActionId != null) {
            store.lookup(opts.parentActionId)?.let { parent ->
                traceId = parent.traceId
                parentSpan = parent.spanId
            }
        }
        val ctx = ActionContext(
            id = UUID.randomUUID(),
            name = opts.name,
            startedAt = now,
            attributes = opts.attributes.toJsonElementMap(),
            parentActionId = opts.parentActionId,
            traceId = traceId,
            spanId = randomSpanId(),
            parentSpanId = parentSpan,
            eventType = cfg.defaultEventType
        )
        store.insert(ctx)
        return ctx.id
    }

    // Finish and send immediately
    suspend fun endAction(
        actionId: UUID,
        status: String = "OK",
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
        config?.appVersion?.let { data["app.version"] = JsonPrimitive(it) }
        config?.deviceInfo?.let { data["device.info"] = JsonPrimitive(it) }

        val event = CloudEvent(
            specversion = "1.0",
            id = UUID.randomUUID().toString(),
            source = cfg.eventProvider,
            type = ctx.eventType,
            time = DateFormatter.dtTime.format(finishedAt),
            traceparent = buildTraceparent(traceId = ctx.traceId, spanId = ctx.spanId),
            data = JsonObject(data)
        )

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
            endAction(id, status = "OK")
            Log.d("BusinessEventsClient", "Action name: $name")
            return result
        } catch (e: Exception) {
            // Avoid re-throwing cancellation exceptions, let them propagate
            if (e is CancellationException) throw e
            try {
                endAction(id, status = "ERROR", error = e.message ?: e.toString())
            } catch (endActionError: Exception) {
                Log.e("BusinessEventsClient", "Failed to send error event: $endActionError")
            }
            throw e
        }
    }

    // MARK: - Internals

    sealed class ClientError : Exception() {
        data object NotConfigured : ClientError()
        data object UnknownAction : ClientError()
        data class BadResponse(val code: Int, val body: String?) : ClientError()
    }

    internal data class ActionContext(
        val id: UUID,
        val name: String,
        val startedAt: Date,
        val attributes: Map<String, JsonElement>,
        val parentActionId: UUID?,
        val traceId: String,
        val spanId: String,
        val parentSpanId: String?,
        val eventType: String
    )

    private var config: Config? = null
    private val store = InMemoryStore()
    private val httpClient = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }

    private suspend fun send(event: CloudEvent, config: Config) = withContext(Dispatchers.IO) {
        val mediaType = "application/cloudevent+json".toMediaType()
        val requestBody = json.encodeToString(event).toRequestBody(mediaType)
        val request = Request.Builder()
            .url(config.endpoint)
            .post(requestBody)
            .apply {
                when (config.auth) {
                    is Auth.ApiToken -> header("Authorization", "Api-Token ${config.auth.token}")
                    is Auth.Bearer -> header("Authorization", "Bearer ${config.auth.token}")
                }
            }
            .header("Content-Type", "application/cloudevent+json")
            .build()

        val response = httpClient.newCall(request).execute()
        val code = response.code
        // 202 means accepted; 400 can be partial success per API docs, but here we treat as error to re-evaluate payload
        if (code != 202) {
            // Try to surface server-provided error content for easier debugging
            val body = response.body?.string() ?: ""
            throw ClientError.BadResponse(code, body)
        }
    }

    // MARK: - Trace helpers

    private fun buildTraceparent(traceId: String, spanId: String, sampled: Boolean = true): String {
        val flags = if (sampled) "01" else "00"
        return "00-$traceId-$spanId-$flags"
    }

    private fun randomId(byteCount: Int): String {
        val bytes = ByteArray(byteCount)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun randomTraceId(): String = randomId(16)
    private fun randomSpanId(): String = randomId(8)
}

// MARK: - CloudEvents payload

@Serializable
private data class CloudEvent(
    val specversion: String,
    val id: String,
    val source: String,
    val type: String,
    val time: String,
    val traceparent: String,
    val data: JsonObject
)

// MARK: - In-memory store (thread-safe)

private class InMemoryStore {
    private val dict = ConcurrentHashMap<UUID, BusinessEventsClient.ActionContext>()
    fun insert(ctx: BusinessEventsClient.ActionContext) { dict[ctx.id] = ctx }
    fun lookup(id: UUID): BusinessEventsClient.ActionContext? = dict[id]
    fun remove(id: UUID): BusinessEventsClient.ActionContext? = dict.remove(id)
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

        BusinessEventsClient.configure(
            BusinessEventsClient.Config(
                endpoint = "https://YOUR_ENV.live.dynatrace.com/api/v2/bizevents/ingest",
                auth = BusinessEventsClient.Auth.ApiToken("dt0c01.abc123......"),
                eventProvider = "com.unitedgames.payment.android",
                defaultEventType = "com.unitedgames.user.action",
                appVersion = BuildConfig.VERSION_NAME,
                deviceInfo = "${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
            )
        )
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