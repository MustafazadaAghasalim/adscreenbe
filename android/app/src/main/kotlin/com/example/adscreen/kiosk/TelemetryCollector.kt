package com.example.adscreen.kiosk

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * TelemetryCollector — Monitors all device sensors and emits structured
 * telemetry JSON at a configurable interval via StateFlow.
 *
 * Tracked metrics:
 *   • Battery: percentage, charging state, battery temperature
 *   • Location: lat/lng/speed from FusedLocationProvider
 *   • Thermals: CPU temperature via SensorManager
 *   • Storage: free/total internal storage
 *   • Network: type, IP address, signal strength
 *   • App State: current creative, kiosk mode status
 *
 * Permissions required in AndroidManifest.xml:
 *   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
 *   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
 *   <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
 *   <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
 *
 * Dependencies (build.gradle):
 *   implementation("com.google.android.gms:play-services-location:21.1.0")
 */
class TelemetryCollector(
    private val context: Context,
    private val tabletId: String
) {
    companion object {
        private const val TAG = "TelemetryCollector"
        private const val DEFAULT_INTERVAL_MS = 30_000L  // 30 seconds
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Mutable state for live sensor values
    // ═══════════════════════════════════════════════════════════════════
    private val _batteryPercent = MutableStateFlow(0)
    private val _chargingState = MutableStateFlow("unknown")
    private val _isCharging = MutableStateFlow(false)
    private val _batteryTemp = MutableStateFlow(0f)

    private val _latitude = MutableStateFlow(0.0)
    private val _longitude = MutableStateFlow(0.0)
    private val _speed = MutableStateFlow(0f)
    private val _locationError = MutableStateFlow<String?>(null)

    private val _cpuTemp = MutableStateFlow(0f)
    private val _thermalHealth = MutableStateFlow("Safe")

    // App state (set externally by the kiosk Activity / service orchestrator)
    private val _appState = MutableStateFlow("Idle")
    val appState: MutableStateFlow<String> = _appState

    private val _currentCreative = MutableStateFlow("None")
    val currentCreative: MutableStateFlow<String> = _currentCreative

    private val _impressionsToday = MutableStateFlow(0)
    val impressionsToday: MutableStateFlow<Int> = _impressionsToday

    // Configurable GPS interval (can be changed via remote command)
    private val _gpsIntervalMs = MutableStateFlow(DEFAULT_INTERVAL_MS)

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var sensorManager: SensorManager? = null
    private var temperatureListener: SensorEventListener? = null

    // ═══════════════════════════════════════════════════════════════════
    //  Battery Monitoring (via Sticky Intent)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Reads the current battery state from the sticky ACTION_BATTERY_CHANGED intent.
     * This is a pull-based approach (called before each telemetry emission).
     */
    fun getBatterySnapshot() {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        intent?.let {
            val level = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            _batteryPercent.value = (level * 100) / scale

            val status = it.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            _isCharging.value = status == BatteryManager.BATTERY_STATUS_CHARGING
                    || status == BatteryManager.BATTERY_STATUS_FULL
            _chargingState.value = when (status) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "Charging"
                BatteryManager.BATTERY_STATUS_FULL -> "Full"
                BatteryManager.BATTERY_STATUS_DISCHARGING -> "Discharging"
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Not Charging"
                else -> "Unknown"
            }

            // Battery temperature is in tenths of °C
            val rawTemp = it.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
            _batteryTemp.value = rawTemp / 10f
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  GPS Monitoring (FusedLocationProvider)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Start continuous GPS updates using Google's FusedLocationProviderClient.
     * Emits location data into StateFlow fields.
     * If GPS is disabled, sets _locationError to "Location Unavailable".
     */
    @SuppressLint("MissingPermission")
    fun startLocationUpdates() {
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(context)

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc: Location = result.lastLocation ?: return
                _latitude.value = loc.latitude
                _longitude.value = loc.longitude
                _speed.value = loc.speed
                _locationError.value = null
                Log.d(TAG, "📍 GPS: ${loc.latitude}, ${loc.longitude} speed=${loc.speed}")
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                if (!availability.isLocationAvailable) {
                    _locationError.value = "Location Unavailable"
                    Log.w(TAG, "⚠️ GPS unavailable — broadcasting Location Error state")
                }
            }
        }

        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            _gpsIntervalMs.value
        ).apply {
            setMinUpdateIntervalMillis(_gpsIntervalMs.value / 2)
            setWaitForAccurateLocation(false)
        }.build()

        fusedLocationClient?.requestLocationUpdates(
            request, locationCallback!!, context.mainLooper
        )
        Log.i(TAG, "📡 Location updates started (interval=${_gpsIntervalMs.value}ms)")
    }

    /**
     * Update GPS reporting interval. Restarts location updates with the new interval.
     */
    fun updateGpsInterval(intervalMs: Long) {
        _gpsIntervalMs.value = intervalMs
        stopLocationUpdates()
        startLocationUpdates()
        Log.i(TAG, "📡 GPS interval updated to ${intervalMs}ms")
    }

    fun stopLocationUpdates() {
        locationCallback?.let { fusedLocationClient?.removeLocationUpdates(it) }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CPU Temperature (SensorManager)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Start monitoring device temperature via hardware sensors.
     * Falls back from TYPE_TEMPERATURE (deprecated but still works on many devices)
     * to TYPE_AMBIENT_TEMPERATURE if available.
     */
    fun startTemperatureMonitoring() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

        val tempSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_TEMPERATURE)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_AMBIENT_TEMPERATURE)

        if (tempSensor != null) {
            temperatureListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    _cpuTemp.value = event.values[0]
                    _thermalHealth.value = when {
                        event.values[0] >= 55f -> "Critical"
                        event.values[0] >= 45f -> "Warning"
                        else -> "Safe"
                    }
                }
                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            sensorManager?.registerListener(
                temperatureListener, tempSensor, SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.i(TAG, "🌡️ Temperature monitoring started (sensor: ${tempSensor.name})")
        } else {
            Log.w(TAG, "⚠️ No temperature sensor available on this device")
        }
    }

    fun stopTemperatureMonitoring() {
        temperatureListener?.let { sensorManager?.unregisterListener(it) }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Build Full Telemetry JSON Payload
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Constructs the complete telemetry JSON object with all monitored metrics.
     * Called periodically by KioskForegroundService on the telemetry timer.
     *
     * @return JSONObject matching the telemetry schema.
     */
    fun buildTelemetryPayload(): JSONObject {
        getBatterySnapshot()  // Refresh battery data before building

        return JSONObject().apply {
            put("type", "telemetry")
            put("tablet_id", tabletId)
            put("timestamp", System.currentTimeMillis().toString())

            // ── Battery ──
            put("battery_percent", _batteryPercent.value)
            put("is_charging", _isCharging.value)
            put("charging_status", _chargingState.value)
            put("temperature_battery", _batteryTemp.value)

            // ── Location ──
            put("latitude", _latitude.value)
            put("longitude", _longitude.value)
            put("speed", _speed.value)
            put("location_error", _locationError.value ?: JSONObject.NULL)

            // ── Thermals ──
            put("temperature_cpu", _cpuTemp.value)
            put("thermal_health", _thermalHealth.value)

            // ── Device Metadata ──
            put("device_model", "${Build.MANUFACTURER} ${Build.MODEL}")
            put("os_version", "Android ${Build.VERSION.RELEASE}")
            put("uptime", formatUptime())

            // ── Network ──
            put("network_type", getNetworkType())
            put("ip_address", getLocalIpAddress())

            // ── Storage ──
            put("storage_free", getStorageFreeGB())
            put("storage_total", getStorageTotalGB())

            // ── Display ──
            put("brightness", getScreenBrightness())

            // ── App State ──
            put("app_state", _appState.value)
            put("current_creative", _currentCreative.value)
            put("impressions_today", _impressionsToday.value)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Utility Methods
    // ═══════════════════════════════════════════════════════════════════

    private fun formatUptime(): String {
        val uptimeMs = SystemClock.elapsedRealtime()
        val hours = uptimeMs / 3_600_000
        val minutes = (uptimeMs % 3_600_000) / 60_000
        return "${hours}h ${minutes}m"
    }

    @SuppressLint("MissingPermission")
    private fun getNetworkType(): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return "None"
        val caps = cm.getNetworkCapabilities(network) ?: return "Unknown"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WiFi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "Other"
        }
    }

    private fun getLocalIpAddress(): String = try {
        NetworkInterface.getNetworkInterfaces().toList()
            .flatMap { it.inetAddresses.toList() }
            .firstOrNull { !it.isLoopbackAddress && it is Inet4Address }
            ?.hostAddress ?: "Unknown"
    } catch (_: Exception) { "Unknown" }

    private fun getStorageFreeGB(): String {
        val stat = StatFs(Environment.getDataDirectory().path)
        val free = stat.availableBlocksLong * stat.blockSizeLong
        return "%.1f GB".format(free / (1024.0 * 1024 * 1024))
    }

    private fun getStorageTotalGB(): String {
        val stat = StatFs(Environment.getDataDirectory().path)
        val total = stat.blockCountLong * stat.blockSizeLong
        return "%.1f GB".format(total / (1024.0 * 1024 * 1024))
    }

    private fun getScreenBrightness(): Float = try {
        Settings.System.getInt(
            context.contentResolver, Settings.System.SCREEN_BRIGHTNESS
        ) / 255f
    } catch (_: Exception) { 0.5f }

    /**
     * Cleanup all sensor listeners and location updates.
     * Call this in the Service's onDestroy().
     */
    fun destroy() {
        stopLocationUpdates()
        stopTemperatureMonitoring()
        Log.i(TAG, "🛑 TelemetryCollector destroyed")
    }
}
