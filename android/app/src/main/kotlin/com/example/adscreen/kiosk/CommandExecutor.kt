package com.example.adscreen.kiosk

import android.app.admin.DevicePolicyManager
import android.app.admin.SystemUpdatePolicy
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.UserManager
import android.provider.Settings
import android.util.Log
import com.example.adscreen.DeviceAdmin
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * CommandExecutor — Executes admin commands received from WebSocket.
 *
 * Supported commands (via JSON "command" field):
 *
 *   KIOSK COMMANDS:
 *     "lock"               → Enter Lock Task Mode (kiosk pin)
 *     "unlock"             → Exit Lock Task Mode
 *
 *   DEVICE COMMANDS:
 *     "reboot"             → Hardware reboot via DPM (requires Device Owner)
 *     "force_refresh"      → Clear ad queue + re-fetch from server
 *     "clear_data"         → Delete downloaded media cache
 *     "wipe_device"        → Factory reset (DANGER — requires confirmation)
 *
 *   SETTINGS COMMANDS:
 *     "set_brightness"     → Override screen brightness (0-100)
 *     "set_volume"         → Lock media volume (0-100)
 *     "lock_usb"           → Restrict USB to charging-only
 *     "unlock_usb"         → Restore USB file transfer
 *     "set_orientation"    → Force landscape/portrait
 *     "set_gps_interval"   → Change GPS reporting frequency
 *     "enable_battery_saver"→ Set battery threshold for power-saving
 *     "set_wifi_only"      → Disable cellular data
 *     "set_adb"            → Enable/disable ADB
 *     "set_auto_update"    → Set system update window (start/end hour)
 *     "set_thermal_threshold" → Set temperature threshold for dimming
 *     "set_memory_cleanup" → Set storage % threshold for auto-cleanup
 *     "set_reboot_schedule"→ Set daily reboot time (HH:MM)
 *
 * Permissions:
 *   - Most commands require Device Owner (DPM.isDeviceOwnerApp)
 *   - Brightness requires WRITE_SETTINGS permission
 *   - Reboot requires Device Owner
 *   - Factory reset requires Device Owner + payload confirmation flag
 */
class CommandExecutor(
    private val context: Context,
    private val scope: CoroutineScope,
    private val onRefreshAds: () -> Unit,                    // Callback to trigger ad re-fetch
    private val onSettingsApplied: (String, Boolean) -> Unit // (command, success) ACK callback
) {
    companion object {
        private const val TAG = "CommandExecutor"
        private const val PREFS_NAME = "adscreen_settings"
    }

    private val dpm: DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val adminComponent = DeviceAdmin.getComponentName(context)
    private val isDeviceOwner = dpm.isDeviceOwnerApp(context.packageName)

    /**
     * Execute a command from a WebSocket JSON message.
     * Expected format: { "type": "command", "command": "...", "payload": {...} }
     */
    fun execute(json: JSONObject) {
        val command = json.optString("command", "")
        val payload = json.optJSONObject("payload") ?: JSONObject()

        Log.i(TAG, "🛡️ Executing command: $command (DO=$isDeviceOwner)")

        try {
            when (command) {
                // ── Kiosk Lock/Unlock ──
                "lock"   -> enterLockTaskMode()
                "unlock" -> exitLockTaskMode()

                // ── Device Commands ──
                "reboot"        -> rebootDevice()
                "force_refresh" -> forceRefresh()
                "clear_data"    -> clearMediaCache()
                "wipe_device"   -> wipeDevice(payload)

                // ── Settings ──
                "set_brightness"        -> setBrightness(payload.optInt("value", 80))
                "set_volume"            -> setVolume(payload.optInt("value", 50))
                "lock_usb"              -> setUsbLockdown(true)
                "unlock_usb"            -> setUsbLockdown(false)
                "set_orientation"       -> setOrientation(payload.optString("mode", "landscape"))
                "set_gps_interval"      -> setGpsInterval(payload.optLong("interval_ms", 30000))
                "enable_battery_saver"  -> setBatterySaverThreshold(payload.optInt("threshold", 15))
                "set_wifi_only"         -> setWifiOnly(payload.optBoolean("enabled", true))
                "set_adb"               -> setAdbEnabled(payload.optBoolean("enabled", false))
                "set_auto_update"       -> setAutoUpdateWindow(
                    payload.optInt("start_hour", 2),
                    payload.optInt("end_hour", 5)
                )
                "set_thermal_threshold" -> setThermalThreshold(payload.optInt("temp_c", 45))
                "set_memory_cleanup"    -> setMemoryCleanupThreshold(payload.optInt("percent", 85))
                "set_reboot_schedule"   -> setDailyReboot(payload.optString("time", "04:00"))

                // ── Screenshot (delegated to ScreenCaptureService) ──
                "take_screenshot" -> {
                    Log.i(TAG, "📸 Screenshot command delegated to ScreenCaptureService")
                }

                // ── Batch Settings ──
                "batch_settings" -> executeBatchSettings(payload)

                else -> Log.w(TAG, "⚠️ Unknown command: $command")
            }
            onSettingsApplied(command, true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Command failed: $command", e)
            onSettingsApplied(command, false)
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  BATCH SETTINGS — apply multiple settings at once
    // ════════════════════════════════════════════════════════════════════

    private fun executeBatchSettings(payload: JSONObject) {
        Log.i(TAG, "📦 Applying batch settings (${payload.length()} keys)")

        if (payload.has("kiosk_lock")) {
            if (payload.optBoolean("kiosk_lock")) enterLockTaskMode()
            else exitLockTaskMode()
        }
        if (payload.has("brightness"))              setBrightness(payload.optInt("brightness", 80))
        if (payload.has("volume"))                  setVolume(payload.optInt("volume", 50))
        if (payload.has("orientation"))             setOrientation(payload.optString("orientation", "landscape"))
        if (payload.has("usb_lockdown"))            setUsbLockdown(payload.optBoolean("usb_lockdown"))
        if (payload.has("wifi_only"))               setWifiOnly(payload.optBoolean("wifi_only"))
        if (payload.has("adb_enabled"))             setAdbEnabled(payload.optBoolean("adb_enabled"))
        if (payload.has("gps_interval_ms"))         setGpsInterval(payload.optLong("gps_interval_ms"))
        if (payload.has("battery_saver_threshold")) setBatterySaverThreshold(payload.optInt("battery_saver_threshold"))
        if (payload.has("thermal_threshold_c"))     setThermalThreshold(payload.optInt("thermal_threshold_c"))
        if (payload.has("memory_cleanup_threshold"))setMemoryCleanupThreshold(payload.optInt("memory_cleanup_threshold"))
        if (payload.has("daily_reboot_time"))       setDailyReboot(payload.optString("daily_reboot_time"))
        if (payload.has("auto_update_start_hour") && payload.has("auto_update_end_hour")) {
            setAutoUpdateWindow(
                payload.optInt("auto_update_start_hour"),
                payload.optInt("auto_update_end_hour")
            )
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  KIOSK MODE (Lock Task Mode)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Enter Lock Task Mode — pins the app to the screen.
     * The actual startLockTask() must be called from the Activity,
     * so we send a local broadcast that the KioskActivity intercepts.
     */
    private fun enterLockTaskMode() {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot lock — not Device Owner")
            return
        }
        // Ensure our package is in the allow list
        dpm.setLockTaskPackages(adminComponent, arrayOf(context.packageName))

        val intent = Intent("com.adscreen.kiosk.ACTION_LOCK_TASK").apply {
            putExtra("lock", true)
        }
        context.sendBroadcast(intent)
        Log.i(TAG, "🔒 Lock Task Mode activated")
    }

    /**
     * Exit Lock Task Mode — un-pins the app.
     * The actual stopLockTask() must be called from the Activity.
     */
    private fun exitLockTaskMode() {
        val intent = Intent("com.adscreen.kiosk.ACTION_LOCK_TASK").apply {
            putExtra("lock", false)
        }
        context.sendBroadcast(intent)
        Log.i(TAG, "🔓 Lock Task Mode deactivated")
    }

    // ════════════════════════════════════════════════════════════════════
    //  DEVICE COMMANDS
    // ════════════════════════════════════════════════════════════════════

    /**
     * Reboot — Requires Device Owner.
     * Uses DevicePolicyManager.reboot() (API 24+).
     */
    private fun rebootDevice() {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot reboot — not Device Owner")
            return
        }
        Log.w(TAG, "⚡ REBOOTING DEVICE NOW")
        dpm.reboot(adminComponent)
    }

    /**
     * Force Refresh — clears local media cache and triggers ad re-fetch.
     */
    private fun forceRefresh() {
        Log.i(TAG, "🔄 Force refresh — clearing queue and re-fetching ads")
        clearMediaCache()
        onRefreshAds()
    }

    /**
     * Clear Media Cache — deletes downloaded ad files from external and internal cache.
     */
    private fun clearMediaCache() {
        var deletedCount = 0
        // External ads directory
        context.getExternalFilesDir("ads")?.listFiles()?.forEach { file ->
            if (file.delete()) deletedCount++
        }
        // Internal cache
        context.cacheDir.listFiles()?.forEach { file ->
            if (file.delete()) deletedCount++
        }
        Log.i(TAG, "✅ Media cache cleared ($deletedCount files deleted)")
    }

    /**
     * Factory Reset — DESTRUCTIVE. Requires Device Owner.
     * Only executes if payload contains "confirm": true
     */
    private fun wipeDevice(payload: JSONObject) {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot wipe — not Device Owner")
            return
        }
        if (!payload.optBoolean("confirm", false)) {
            Log.w(TAG, "⚠️ Wipe rejected — missing confirmation flag")
            return
        }
        Log.w(TAG, "🔥 FACTORY RESET INITIATED")
        dpm.wipeData(0)
    }

    // ════════════════════════════════════════════════════════════════════
    //  SETTINGS
    // ════════════════════════════════════════════════════════════════════

    /**
     * Brightness Override (0–100%) → Settings.System.SCREEN_BRIGHTNESS (0–255).
     * Requires: WRITE_SETTINGS permission (granted via Settings UI or Device Owner).
     */
    private fun setBrightness(percent: Int) {
        val value = (percent.coerceIn(0, 100) * 255) / 100
        // Disable auto-brightness first
        Settings.System.putInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS_MODE,
            Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
        )
        Settings.System.putInt(
            context.contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            value
        )
        Log.i(TAG, "💡 Brightness set to $percent% (raw=$value/255)")
    }

    /**
     * Volume Lock — Force media volume to a percentage.
     * Stores the locked volume in SharedPrefs so VolumeEnforcer can reset it
     * when the user presses physical volume buttons.
     */
    private fun setVolume(percent: Int) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVol = (percent.coerceIn(0, 100) * maxVol) / 100
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, 0)

        // Store for VolumeEnforcer
        getPrefs().edit()
            .putInt("locked_volume", targetVol)
            .putBoolean("volume_locked", true)
            .apply()

        Log.i(TAG, "🔊 Volume locked to $percent% (raw=$targetVol/$maxVol)")
    }

    /**
     * USB Lockdown — Restrict USB to charging-only (no MTP/PTP file transfer).
     * Requires Device Owner for addUserRestriction(DISALLOW_USB_FILE_TRANSFER).
     */
    private fun setUsbLockdown(locked: Boolean) {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot control USB — not Device Owner")
            return
        }
        if (locked) {
            dpm.addUserRestriction(adminComponent, UserManager.DISALLOW_USB_FILE_TRANSFER)
            Log.i(TAG, "🔒 USB file transfer disabled (charging only)")
        } else {
            dpm.clearUserRestriction(adminComponent, UserManager.DISALLOW_USB_FILE_TRANSFER)
            Log.i(TAG, "🔓 USB file transfer enabled")
        }
    }

    /**
     * Screen Orientation Lock — sends broadcast to KioskActivity.
     * The Activity calls setRequestedOrientation(SCREEN_ORIENTATION_LANDSCAPE/PORTRAIT).
     */
    private fun setOrientation(mode: String) {
        val intent = Intent("com.adscreen.kiosk.ACTION_SET_ORIENTATION").apply {
            putExtra("orientation", mode) // "landscape" or "portrait"
        }
        context.sendBroadcast(intent)
        Log.i(TAG, "📐 Orientation locked to: $mode")
    }

    /**
     * GPS Reporting Interval — stores in SharedPrefs for TelemetryCollector.
     */
    private fun setGpsInterval(intervalMs: Long) {
        getPrefs().edit()
            .putLong("gps_interval_ms", intervalMs)
            .apply()
        Log.i(TAG, "📡 GPS interval set to ${intervalMs}ms")
    }

    /**
     * Battery Saver Threshold — stores in SharedPrefs for battery monitoring.
     */
    private fun setBatterySaverThreshold(threshold: Int) {
        getPrefs().edit()
            .putInt("battery_saver_threshold", threshold)
            .apply()
        Log.i(TAG, "🔋 Battery saver threshold: $threshold%")
    }

    /**
     * Wi-Fi Only Mode — disables configuration of mobile networks.
     * Requires Device Owner.
     */
    private fun setWifiOnly(enabled: Boolean) {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot toggle Wi-Fi only — not Device Owner")
            return
        }
        if (enabled) {
            dpm.addUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
            Log.i(TAG, "📶 Wi-Fi only mode enabled")
        } else {
            dpm.clearUserRestriction(adminComponent, UserManager.DISALLOW_CONFIG_MOBILE_NETWORKS)
            Log.i(TAG, "📶 Cellular data re-enabled")
        }
    }

    /**
     * ADB Debug Mode — toggle global ADB setting.
     * Requires Device Owner with WRITE_SECURE_SETTINGS.
     */
    private fun setAdbEnabled(enabled: Boolean) {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot toggle ADB — not Device Owner")
            return
        }
        try {
            Settings.Global.putInt(
                context.contentResolver,
                Settings.Global.ADB_ENABLED,
                if (enabled) 1 else 0
            )
            Log.i(TAG, "🐛 ADB ${if (enabled) "enabled" else "disabled"}")
        } catch (e: SecurityException) {
            Log.e(TAG, "Cannot toggle ADB — requires WRITE_SECURE_SETTINGS grant", e)
        }
    }

    /**
     * Auto-Update Window — sets DPM system update policy.
     * Only installs system updates between start_hour and end_hour.
     * Requires Device Owner.
     */
    private fun setAutoUpdateWindow(startHour: Int, endHour: Int) {
        if (!isDeviceOwner) {
            Log.e(TAG, "Cannot set update policy — not Device Owner")
            return
        }
        val startMinutes = startHour * 60
        val endMinutes = endHour * 60
        dpm.setSystemUpdatePolicy(
            adminComponent,
            SystemUpdatePolicy.createWindowedInstallPolicy(startMinutes, endMinutes)
        )
        Log.i(TAG, "🔄 Auto-update window: ${startHour}:00 - ${endHour}:00")
    }

    /**
     * Thermal Protection threshold — stored in SharedPrefs.
     * TelemetryCollector monitors temperature and dims screen if exceeded.
     */
    private fun setThermalThreshold(tempC: Int) {
        getPrefs().edit()
            .putInt("thermal_threshold_c", tempC)
            .apply()
        Log.i(TAG, "🌡️ Thermal threshold: ${tempC}°C")
    }

    /**
     * Memory Auto-Cleanup threshold — stored in SharedPrefs.
     * When storage usage exceeds this %, old cached media is auto-purged.
     */
    private fun setMemoryCleanupThreshold(percent: Int) {
        getPrefs().edit()
            .putInt("memory_cleanup_threshold", percent)
            .apply()
        Log.i(TAG, "💾 Memory cleanup threshold: $percent%")
    }

    /**
     * Daily Reboot Schedule — stores time and schedules via AlarmManager.
     */
    private fun setDailyReboot(time: String) {
        getPrefs().edit()
            .putString("daily_reboot_time", time)
            .apply()
        ScheduledRebootManager.schedule(context, time)
        Log.i(TAG, "⏰ Daily reboot scheduled at $time")
    }

    // ── SharedPrefs helper ──
    private fun getPrefs() =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
