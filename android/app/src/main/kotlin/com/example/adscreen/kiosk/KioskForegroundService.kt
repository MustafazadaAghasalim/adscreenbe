package com.example.adscreen.kiosk

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.json.JSONObject

/**
 * KioskForegroundService — Persistent foreground service that:
 *   1. Maintains a WebSocket connection to the Adscreen server
 *   2. Broadcasts telemetry every 30 seconds
 *   3. Listens for and executes remote commands
 *   4. Survives Doze mode and app backgrounding
 *
 * START:
 *   val intent = Intent(this, KioskForegroundService::class.java)
 *   intent.putExtra("SERVER_URL", "wss://adscreentaxi.azurewebsites.net/ws")
 *   ContextCompat.startForegroundService(this, intent)
 *
 * PERMISSIONS (AndroidManifest.xml):
 *   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
 *   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
 *
 *   <service
 *       android:name=".KioskForegroundService"
 *       android:foregroundServiceType="location"
 *       android:exported="false" />
 */
class KioskForegroundService : Service() {

    companion object {
        private const val TAG = "KioskService"
        private const val CHANNEL_ID = "adscreen_kiosk_channel"
        private const val NOTIFICATION_ID = 1001
        private const val DEFAULT_TELEMETRY_INTERVAL_MS = 30_000L
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var wsManager: WebSocketManager
    private lateinit var telemetryCollector: TelemetryCollector
    private lateinit var commandExecutor: CommandExecutor

    private var telemetryJob: Job? = null
    private var commandListenerJob: Job? = null

    @SuppressLint("HardwareIds")
    private fun getTabletId(): String {
        val androidId = Settings.Secure.getString(
            contentResolver, Settings.Secure.ANDROID_ID
        )
        return "tablet_$androidId"
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Service Lifecycle
    // ═══════════════════════════════════════════════════════════════════

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Initializing..."))
        Log.i(TAG, "🚀 KioskForegroundService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val serverUrl = intent?.getStringExtra("SERVER_URL")
            ?: "wss://adscreentaxi.azurewebsites.net"
        val tabletId = getTabletId()

        Log.i(TAG, "🚀 Starting with server=$serverUrl tablet=$tabletId")

        // ── Initialize Components ──
        wsManager = WebSocketManager(serverUrl, tabletId, serviceScope)
        telemetryCollector = TelemetryCollector(this, tabletId)
        commandExecutor = CommandExecutor(
            context = this,
            scope = serviceScope,
            onRefreshAds = {
                // Send local broadcast to the KioskActivity to reload ads
                sendBroadcast(Intent("com.adscreen.kiosk.REFRESH_ADS"))
            },
            onSettingsApplied = { cmd, success ->
                // Send ACK back to server so dashboard knows the command executed
                val ack = JSONObject().apply {
                    put("type", "command_ack")
                    put("tablet_id", tabletId)
                    put("command", cmd)
                    put("success", success)
                    put("timestamp", System.currentTimeMillis())
                }
                wsManager.send(ack)
            }
        )

        // ── Start connections & sensors ──
        wsManager.connect()
        telemetryCollector.startLocationUpdates()
        telemetryCollector.startTemperatureMonitoring()

        // ── Telemetry broadcast loop ──
        telemetryJob?.cancel()
        telemetryJob = serviceScope.launch {
            while (isActive) {
                if (wsManager.connectionState.value ==
                    WebSocketManager.ConnectionState.CONNECTED
                ) {
                    val payload = telemetryCollector.buildTelemetryPayload()
                    wsManager.send(payload)
                    Log.d(TAG, "📡 Telemetry sent: " +
                        "battery=${payload.optInt("battery_percent")}% " +
                        "charging=${payload.optString("charging_status")} " +
                        "lat=${payload.optDouble("latitude")} " +
                        "lng=${payload.optDouble("longitude")}"
                    )
                }
                delay(DEFAULT_TELEMETRY_INTERVAL_MS)
            }
        }

        // ── Command listener ──
        commandListenerJob?.cancel()
        commandListenerJob = serviceScope.launch {
            wsManager.incomingMessages.collect { message ->
                val type = message.optString("type", "")
                Log.d(TAG, "📩 Message received: type=$type")

                val command = message.optString("command", "")
                if (command.isNotEmpty()) {
                    commandExecutor.execute(message)
                    return@collect
                }

                when (type) {
                    "command", "admin_command" -> {
                        commandExecutor.execute(message)
                    }
                    "reboot", "lock", "unlock", "refresh_ads", "brightness", "screen_wipe" -> {
                        // Normalize direct typed commands into CommandExecutor shape.
                        // Example incoming payload: { type: "reboot", command: "reboot", ... }
                        // If command is missing, derive from type.
                        if (!message.has("command") || message.optString("command").isEmpty()) {
                            val normalizedCommand = when (type) {
                                "screen_wipe" -> "force_refresh"
                                "refresh_ads" -> "force_refresh"
                                else -> type
                            }
                            message.put("command", normalizedCommand)
                        } else if (message.optString("command") == "screen_wipe") {
                            message.put("command", "force_refresh")
                        }
                        commandExecutor.execute(message)
                    }
                    "settings_update" -> {
                        commandExecutor.execute(message)
                    }
                    "take_screenshot" -> {
                        // Forward to ScreenCaptureService via local broadcast
                        sendBroadcast(Intent("com.adscreen.kiosk.TAKE_SCREENSHOT"))
                    }
                    "ad_update" -> {
                        // Forward to ad display handler
                        val adIntent = Intent("com.adscreen.kiosk.AD_UPDATE").apply {
                            putExtra("payload", message.toString())
                        }
                        sendBroadcast(adIntent)
                    }
                    else -> Log.d(TAG, "ℹ️ Unhandled message type: $type")
                }
            }
        }

        // ── Update notification with connection state ──
        serviceScope.launch {
            wsManager.connectionState.collect { state ->
                val statusText = when (state) {
                    WebSocketManager.ConnectionState.CONNECTED -> "🟢 Connected to server"
                    WebSocketManager.ConnectionState.CONNECTING -> "🟡 Connecting..."
                    WebSocketManager.ConnectionState.DISCONNECTED -> "🔴 Disconnected — reconnecting"
                }
                updateNotification(statusText)
            }
        }

        // ── Monitor battery saver threshold ──
        serviceScope.launch {
            while (isActive) {
                checkBatterySaverThreshold()
                delay(60_000) // Check every 60s
            }
        }

        // ── Monitor storage cleanup threshold ──
        serviceScope.launch {
            while (isActive) {
                checkStorageCleanupThreshold()
                delay(300_000) // Check every 5 min
            }
        }

        return START_STICKY // Restart if killed by OS
    }

    override fun onDestroy() {
        super.onDestroy()
        telemetryJob?.cancel()
        commandListenerJob?.cancel()
        wsManager.disconnect()
        telemetryCollector.destroy()
        serviceScope.cancel()
        Log.i(TAG, "🛑 KioskForegroundService destroyed")
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Automated Monitoring (Battery Saver & Storage Cleanup)
    // ═══════════════════════════════════════════════════════════════════

    private fun checkBatterySaverThreshold() {
        val prefs = getSharedPreferences("adscreen_settings", MODE_PRIVATE)
        val threshold = prefs.getInt("battery_saver_threshold", 15)
        val payload = telemetryCollector.buildTelemetryPayload()
        val batteryPercent = payload.optInt("battery_percent", 100)

        if (batteryPercent <= threshold && !payload.optBoolean("is_charging", false)) {
            Log.w(TAG, "🔋 Battery at $batteryPercent% — below threshold $threshold%")
            // Dim screen to conserve power
            try {
                Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    30 // Very dim
                )
            } catch (_: Exception) {}
        }
    }

    private fun checkStorageCleanupThreshold() {
        val prefs = getSharedPreferences("adscreen_settings", MODE_PRIVATE)
        val threshold = prefs.getInt("memory_cleanup_threshold", 85)
        val payload = telemetryCollector.buildTelemetryPayload()

        val freeStr = payload.optString("storage_free", "0").replace(" GB", "")
        val totalStr = payload.optString("storage_total", "1").replace(" GB", "")

        try {
            val free = freeStr.toFloat()
            val total = totalStr.toFloat()
            val usedPercent = ((total - free) / total * 100).toInt()

            if (usedPercent >= threshold) {
                Log.w(TAG, "💾 Storage at $usedPercent% — exceeds threshold $threshold%")
                // Auto-cleanup old cached media
                val adsDir = getExternalFilesDir("ads")
                val files = adsDir?.listFiles()?.sortedBy { it.lastModified() }
                files?.take(files.size / 3)?.forEach { file ->
                    if (file.delete()) Log.d(TAG, "🗑️ Auto-cleaned: ${file.name}")
                }
            }
        } catch (_: Exception) {}
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Notification Management
    // ═══════════════════════════════════════════════════════════════════

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Adscreen Kiosk Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the Adscreen kiosk running in the background"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(contentText: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Adscreen Kiosk")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(contentText))
    }
}
