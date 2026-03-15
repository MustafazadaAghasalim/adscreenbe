package com.example.adscreen.kiosk

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * WebSocketManager — Persistent, auto-reconnecting WebSocket connection.
 *
 * Uses OkHttp WebSocket with:
 *   - 15s ping interval (keeps alive through NATs/proxies)
 *   - Exponential backoff reconnection (2s → 4s → 8s → max 60s)
 *   - SharedFlow for incoming message dispatch
 *   - Coroutine-safe send() method
 *
 * Dependencies (build.gradle):
 *   implementation("com.squareup.okhttp3:okhttp:4.12.0")
 *   implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
 */
class WebSocketManager(
    private val serverUrl: String,      // "wss://adscreen.az/ws"
    private val tabletId: String,
    private val scope: CoroutineScope
) {
    companion object {
        private const val TAG = "WebSocketMgr"
        private const val PING_INTERVAL_SEC = 15L
        private const val INITIAL_RECONNECT_DELAY_MS = 2000L
        private const val MAX_RECONNECT_DELAY_MS = 60_000L
    }

    // ── Connection state observable ──
    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    // ── Incoming messages (commands from server) ──
    private val _incomingMessages = MutableSharedFlow<JSONObject>(
        replay = 0,
        extraBufferCapacity = 64
    )
    val incomingMessages: SharedFlow<JSONObject> = _incomingMessages.asSharedFlow()

    private var webSocket: WebSocket? = null
    private var reconnectDelay = INITIAL_RECONNECT_DELAY_MS
    private var reconnectJob: Job? = null
    private var isManualClose = false

    private val client = OkHttpClient.Builder()
        .pingInterval(PING_INTERVAL_SEC, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)       // No read timeout for WebSocket
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    enum class ConnectionState {
        DISCONNECTED, CONNECTING, CONNECTED
    }

    /**
     * Establish WebSocket connection.
     * Appends tablet_id as query parameter for server-side routing.
     */
    fun connect() {
        if (_connectionState.value == ConnectionState.CONNECTED) return
        isManualClose = false
        _connectionState.value = ConnectionState.CONNECTING

        val wsUrl = "$serverUrl?tablet_id=$tabletId"
        val request = Request.Builder().url(wsUrl).build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {

            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "✅ WebSocket connected to $serverUrl")
                _connectionState.value = ConnectionState.CONNECTED
                reconnectDelay = INITIAL_RECONNECT_DELAY_MS

                // Send registration message immediately
                val registration = JSONObject().apply {
                    put("type", "register")
                    put("tablet_id", tabletId)
                    put("device_model",
                        "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}")
                    put("os_version", "Android ${android.os.Build.VERSION.RELEASE}")
                }
                send(registration)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val json = JSONObject(text)
                    Log.d(TAG, "📩 Received: ${json.optString("type", "unknown")}")
                    scope.launch { _incomingMessages.emit(json) }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse message: $text", e)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.w(TAG, "⚠️ Server closing: $code $reason")
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.w(TAG, "🔴 WebSocket closed: $code $reason")
                _connectionState.value = ConnectionState.DISCONNECTED
                if (!isManualClose) scheduleReconnect()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "❌ WebSocket failure: ${t.message}")
                _connectionState.value = ConnectionState.DISCONNECTED
                if (!isManualClose) scheduleReconnect()
            }
        })
    }

    /**
     * Send a JSON message through the WebSocket.
     * @return true if the message was enqueued, false if not connected.
     */
    fun send(json: JSONObject): Boolean {
        return webSocket?.send(json.toString()) ?: false.also {
            Log.w(TAG, "Cannot send — WebSocket not connected")
        }
    }

    /**
     * Gracefully close the WebSocket connection.
     * Cancels any pending reconnection attempts.
     */
    fun disconnect() {
        isManualClose = true
        reconnectJob?.cancel()
        webSocket?.close(1000, "Client closing")
        _connectionState.value = ConnectionState.DISCONNECTED
    }

    /**
     * Schedule a reconnection attempt with exponential backoff.
     * Delay doubles on each attempt: 2s → 4s → 8s → 16s → ... → max 60s.
     */
    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            Log.i(TAG, "🔄 Reconnecting in ${reconnectDelay}ms...")
            delay(reconnectDelay)
            reconnectDelay = (reconnectDelay * 2).coerceAtMost(MAX_RECONNECT_DELAY_MS)
            connect()
        }
    }
}
