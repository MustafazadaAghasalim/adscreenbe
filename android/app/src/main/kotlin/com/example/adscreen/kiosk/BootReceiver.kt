package com.example.adscreen.kiosk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * BootReceiver — Restarts the KioskForegroundService after device boot.
 *
 * This ensures the kiosk service is always running, even after a reboot
 * (scheduled or unexpected). The service will reconnect to the WebSocket
 * server and resume telemetry broadcasting automatically.
 *
 * Register in AndroidManifest.xml:
 *   <receiver android:name=".BootReceiver" android:exported="true">
 *     <intent-filter>
 *       <action android:name="android.intent.action.BOOT_COMPLETED" />
 *     </intent-filter>
 *   </receiver>
 *
 * Permission required:
 *   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.i(TAG, "📱 Device boot detected — starting KioskForegroundService")

        // Retrieve stored server URL (fallback to default)
        val prefs = context.getSharedPreferences("adscreen_settings", Context.MODE_PRIVATE)
        val serverUrl = prefs.getString(
            "server_url",
            "wss://adscreen.az/ws"
        )

        val serviceIntent = Intent(context, KioskForegroundService::class.java).apply {
            putExtra("SERVER_URL", serverUrl)
        }

        // Use startForegroundService for Android 8+ (API 26+)
        ContextCompat.startForegroundService(context, serviceIntent)

        // Launch the main activity
        val activityIntent = Intent(context, com.example.adscreen.MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try {
            context.startActivity(activityIntent)
            Log.i(TAG, "🚀 Launched MainActivity successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to launch MainActivity", e)
        }

        // Re-schedule daily reboot if configured
        val rebootTime = prefs.getString("daily_reboot_time", null)
        if (!rebootTime.isNullOrEmpty()) {
            ScheduledRebootManager.schedule(context, rebootTime)
            Log.i(TAG, "⏰ Re-scheduled daily reboot for $rebootTime")
        }

        Log.i(TAG, "✅ Boot recovery complete")
    }
}
