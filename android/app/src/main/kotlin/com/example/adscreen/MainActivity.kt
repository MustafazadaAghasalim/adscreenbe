package com.example.adscreen

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import android.net.wifi.WifiManager
import android.view.View
import android.view.WindowManager
import android.os.Build
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.os.UserManager
import android.view.MotionEvent
import android.graphics.Rect
import android.app.ActivityManager
import com.example.adscreen.kiosk.ScreenCaptureHelper
import com.example.adscreen.kiosk.SilentInstaller

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.adscreen.kiosk/telemetry"
    private val SETTINGS_CHANNEL = "com.adscreen.kiosk/settings"
    private val MEMORY_CHANNEL = "com.example.adscreen/memory"
    private val RESTART_CHANNEL = "com.example.adscreen/restart"
    private val AUDIO_CHANNEL = "com.example.adscreen/audio"
    private val CAPTURE_CHANNEL = "com.adscreen.kiosk/screen_capture"
    private val INSTALL_CHANNEL = "com.adscreen.kiosk/silent_install"
    private var isKioskDesired = true // Default to true
    private val edgeThreshold = 40 // pixels from screen edge to block

    companion object {
        private const val REQUEST_CODE_PROJECTION = 9001
    }

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (isKioskDesired) {
            val keyCode = event.keyCode
            if (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP || 
                keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN ||
                keyCode == android.view.KeyEvent.KEYCODE_HOME ||
                keyCode == android.view.KeyEvent.KEYCODE_APP_SWITCH ||
                keyCode == android.view.KeyEvent.KEYCODE_BACK) {
                return true // Consume the event - block all navigation keys
            }
        }
        return super.dispatchKeyEvent(event)
    }

    // Block edge swipe gestures by consuming touch events near screen edges
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (isKioskDesired) {
            val x = event.x.toInt()
            val y = event.y.toInt()
            val screenWidth = window.decorView.width
            val screenHeight = window.decorView.height

            // Block touches near left edge (back gesture)
            if (x < edgeThreshold) {
                return true // Consume the event
            }
            // Block touches near right edge (back gesture)
            if (x > screenWidth - edgeThreshold) {
                return true // Consume the event
            }
            // Block touches near bottom edge (home/recent apps gesture)
            if (y > screenHeight - edgeThreshold) {
                return true // Consume the event
            }
            // Block touches near top edge (status bar pull-down)
            if (y < edgeThreshold) {
                return true // Consume the event
            }
        }
        return super.dispatchTouchEvent(event)
    }

    // Block back button completely in kiosk mode
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!isKioskDesired) {
            super.onBackPressed()
        }
        // Do nothing when kiosk mode is active - block back button
    }

    // Prevent the activity from being destroyed by multi-window/task management
    override fun onUserLeaveHint() {
        if (isKioskDesired) {
            // Do nothing - prevent leaving the app
        } else {
            super.onUserLeaveHint()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminName = ComponentName(this, DeviceAdmin::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getBatteryTemperature" -> {
                        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val temp = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
                        result.success(temp / 10.0) // Convert to Celsius
                    }
                    "getScreenBrightness" -> {
                        try {
                            val brightness = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                            result.success(brightness / 255.0) // Convert to 0.0 - 1.0
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Brightness not available: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "Brightness not available: ${e.message}", null)
                        }
                    }
                    "getWifiRssi" -> {
                        try {
                            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            val wifiInfo = wifiManager.connectionInfo
                            result.success(wifiInfo.rssi)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "WiFi RSSI not available: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "WiFi RSSI not available: ${e.message}", null)
                        }
                    }
                    "setScreenBrightness" -> {
                        val brightness = call.argument<Double>("brightness") ?: 0.5
                        try {
                            val lp = window.attributes
                            lp.screenBrightness = brightness.toFloat()
                            window.attributes = lp
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Cannot set screen brightness: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to set brightness: ${e.message}", null)
                        }
                    }
                    "startKiosk" -> {
                        isKioskDesired = true
                        try {
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.setStatusBarDisabled(adminName, true)
                                dpm.setLockTaskPackages(adminName, arrayOf(packageName))
                                dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
                                dpm.addUserRestriction(adminName, "no_adjust_volume")
                                startLockTask()
                                result.success(true)
                            } else {
                                result.error("NOT_OWNER", "Not device owner", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Kiosk mode security error: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to start kiosk: ${e.message}", null)
                        }
                    }
                    "stopKiosk" -> {
                        isKioskDesired = false
                        try {
                            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                            if (activityManager.lockTaskModeState != android.app.ActivityManager.LOCK_TASK_MODE_NONE) {
                                stopLockTask()
                            }
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.setStatusBarDisabled(adminName, false)
                                dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS)
                                dpm.clearUserRestriction(adminName, "no_adjust_volume")
                                dpm.clearUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT)
                                dpm.clearUserRestriction(adminName, "no_config_notifications")
                                dpm.clearUserRestriction(adminName, "no_status_bar")
                                dpm.clearPackagePersistentPreferredActivities(adminName, packageName)
                            }
                            result.success(true)
                        } catch (e: SecurityException) {
                            android.util.Log.e("MainActivity", "Security error in stopKiosk: ${e.message}")
                            result.error("SECURITY_ERROR", "Kiosk stop security error: ${e.message}", null)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Error in stopKiosk: ${e.message}")
                            result.error("ERROR", "Failed to stop kiosk: ${e.message}", null)
                        }
                    }
                    "exitToHome" -> {
                        try {
                            val intent = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Cannot exit to home: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to exit to home: ${e.message}", null)
                        }
                    }
                    "killApp" -> {
                        try {
                            // Ensure all restrictions are cleared before killing
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.setStatusBarDisabled(adminName, false)
                                dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS)
                                dpm.clearUserRestriction(adminName, "no_adjust_volume")
                                dpm.clearUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT)
                                dpm.clearUserRestriction(adminName, "no_config_notifications")
                                dpm.clearUserRestriction(adminName, "no_status_bar")
                                dpm.clearPackagePersistentPreferredActivities(adminName, packageName)
                            }

                            finishAndRemoveTask()

                            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                android.util.Log.d("MainActivity", "Force killing process now...")
                                android.os.Process.killProcess(android.os.Process.myPid())
                                System.exit(0)
                            }, 50)

                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Failed to adjust kiosk restrictions: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to kill app: ${e.message}", null)
                        }
                    }
                    "rebootDevice" -> {
                        try {
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                dpm.reboot(adminName)
                                result.success(true)
                            } else {
                                result.error("NOT_OWNER", "Not device owner", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Reboot security error: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to reboot device: ${e.message}", null)
                        }
                    }
                    "shutdownDevice" -> {
                        try {
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                // Attempt shutdown via system intent
                                val intent = Intent("com.android.internal.intent.action.REQUEST_SHUTDOWN")
                                intent.putExtra("android.intent.extra.KEY_CONFIRM", false)
                                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("NOT_OWNER", "Not device owner", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Shutdown security error: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to shutdown device: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("SECURITY_ERROR", "Security exception: ${e.message}", null)
            } catch (e: Exception) {
                result.error("ERROR", "Unexpected error: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  MEMORY CHANNEL — Native memory monitoring & GC  
        //  (Fixes orphan: Flutter side uses this but had no native handler)
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEMORY_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getMemoryInfo" -> {
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memInfo)
                        val runtime = Runtime.getRuntime()
                        result.success(mapOf(
                            "totalMem" to memInfo.totalMem,
                            "availMem" to memInfo.availMem,
                            "lowMemory" to memInfo.lowMemory,
                            "threshold" to memInfo.threshold,
                            "javaHeapMax" to runtime.maxMemory(),
                            "javaHeapUsed" to (runtime.totalMemory() - runtime.freeMemory()),
                            "javaHeapFree" to runtime.freeMemory()
                        ))
                    }
                    "forceGC" -> {
                        System.gc()
                        Runtime.getRuntime().gc()
                        result.success(true)
                    }
                    "trimMemory" -> {
                        // Trigger onTrimMemory callback at COMPLETE level
                        val level = call.argument<Int>("level") ?: 80
                        System.gc()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Memory operation failed: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  RESTART CHANNEL — Hot restart scheduling
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RESTART_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "scheduleRestart" -> {
                        val delayMs = call.argument<Int>("delayMs") ?: 0
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            // Recreate the activity to force Flutter engine restart
                            recreate()
                        }, delayMs.toLong())
                        result.success(true)
                    }
                    "getUptime" -> {
                        val uptimeMs = android.os.SystemClock.elapsedRealtime()
                        result.success(uptimeMs)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Restart operation failed: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  AUDIO CHANNEL — Volume control for ad playback
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                when (call.method) {
                    "setVolume" -> {
                        val volume = call.argument<Double>("volume") ?: 0.5
                        val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                        val targetVol = (volume * maxVol).toInt().coerceIn(0, maxVol)
                        audioManager.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, targetVol, 0)
                        result.success(true)
                    }
                    "getVolume" -> {
                        val currentVol = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
                        val maxVol = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                        result.success(currentVol.toDouble() / maxVol.toDouble())
                    }
                    "mute" -> {
                        audioManager.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, 0, 0)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Audio operation failed: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  SCREEN CAPTURE CHANNEL — Remote screenshot & streaming
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestConsent" -> {
                        ScreenCaptureHelper.requestProjection(this, REQUEST_CODE_PROJECTION)
                        result.success(true)
                    }
                    "takeScreenshot" -> {
                        val url = call.argument<String>("uploadUrl") ?: "https://adscreen.az/api/screenshot"
                        val tabletId = call.argument<String>("tabletId") ?: "unknown"
                        ScreenCaptureHelper.takeScreenshot(this, url, tabletId)
                        result.success(true)
                    }
                    "startStream" -> {
                        val url = call.argument<String>("uploadUrl") ?: "https://adscreen.az/api/screenshot"
                        val tabletId = call.argument<String>("tabletId") ?: "unknown"
                        ScreenCaptureHelper.startStream(this, url, tabletId)
                        result.success(true)
                    }
                    "stopStream" -> {
                        ScreenCaptureHelper.stopStream(this)
                        result.success(true)
                    }
                    "hasConsent" -> {
                        result.success(ScreenCaptureHelper.hasConsent(this))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Screen capture error: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  SILENT INSTALL CHANNEL — OTA APK updates
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "installApk" -> {
                        val url = call.argument<String>("url") ?: ""
                        val versionCode = call.argument<Int>("versionCode")?.toLong() ?: 0L
                        val sha256 = call.argument<String>("sha256")
                        val force = call.argument<Boolean>("force") ?: false

                        if (url.isEmpty()) {
                            result.error("INVALID", "APK URL is required", null)
                            return@setMethodCallHandler
                        }

                        val installer = SilentInstaller(
                            context = this,
                            scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO),
                            onResult = { success, message ->
                                android.util.Log.i("SilentInstall", "Result: success=$success msg=$message")
                            }
                        )
                        installer.downloadAndInstall(url, versionCode, sha256, force)
                        result.success(true)
                    }
                    "getVersionInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "versionName" to (info.versionName ?: "unknown"),
                            "versionCode" to versionCode,
                            "packageName" to packageName
                        ))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERROR", "Install error: ${e.message}", null)
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        //  SETTINGS CHANNEL
        // ═══════════════════════════════════════════════════════════════════
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setBrightness" -> {
                        val brightness = call.argument<Double>("value") ?: 0.5
                        try {
                            val lp = window.attributes
                            lp.screenBrightness = brightness.toFloat()
                            window.attributes = lp
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Security exception modifying Brightness: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "setRotationLock" -> {
                        val mode = call.argument<String>("mode") ?: "landscape"
                        try {
                            if (Settings.System.canWrite(applicationContext)) {
                                if (mode == "auto") {
                                    Settings.System.putInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1)
                                } else {
                                    Settings.System.putInt(contentResolver, Settings.System.ACCELEROMETER_ROTATION, 0)
                                    val orientation = if (mode == "landscape") 1 else 0 // 1 = landscape, 0 = portrait
                                    Settings.System.putInt(contentResolver, Settings.System.USER_ROTATION, orientation)
                                }
                                result.success(true)
                            } else {
                                result.error("NO_PERMISSION", "WRITE_SETTINGS permission required", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Security exception modifying Rotation: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "setUsbDisabled" -> {
                        val disabled = call.argument<Boolean>("disabled") ?: false
                        try {
                            if (dpm.isDeviceOwnerApp(packageName)) {
                                if (disabled) {
                                    dpm.addUserRestriction(adminName, UserManager.DISALLOW_USB_FILE_TRANSFER)
                                } else {
                                    dpm.clearUserRestriction(adminName, UserManager.DISALLOW_USB_FILE_TRANSFER)
                                }
                                result.success(true)
                            } else {
                                result.error("NOT_OWNER", "Not device owner", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Security exception modifying USB: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "setScreenTimeout" -> {
                        val minutes = call.argument<Int>("minutes") ?: 0
                        try {
                            if (Settings.System.canWrite(applicationContext)) {
                                val millis = if (minutes <= 0) -1 else minutes * 60 * 1000
                                Settings.System.putInt(contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, millis)
                                result.success(true)
                            } else {
                                result.error("NO_PERMISSION", "WRITE_SETTINGS permission required", null)
                            }
                        } catch (e: SecurityException) {
                            result.error("SECURITY_ERROR", "Security exception modifying Timeout: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("SECURITY_ERROR", "Security exception: ${e.message}", null)
            } catch (e: Exception) {
                result.error("ERROR", "Unexpected error: ${e.message}", null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Bypass lock screen and turn screen on
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Request screen capture consent on first launch (one-time)
        if (!ScreenCaptureHelper.hasConsent(this)) {
            ScreenCaptureHelper.requestProjection(this, REQUEST_CODE_PROJECTION)
        }

        // Start MDM Background Service
        val serviceIntent = Intent(this, com.example.adscreen.kiosk.KioskForegroundService::class.java).apply {
            putExtra("SERVER_URL", "wss://adscreen.az/ws")
        }
        try {
            androidx.core.content.ContextCompat.startForegroundService(this, serviceIntent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to start Kiosk service", e)
        }
        
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminName = ComponentName(this, DeviceAdmin::class.java)
        
        if (dpm.isDeviceOwnerApp(packageName)) {
            android.util.Log.d("MainActivity", "Device Owner confirmed. Enabling full kiosk mode...")
            
            // Whitelist ourselves for lock task
            dpm.setLockTaskPackages(adminName, arrayOf(packageName))
            
            // Disable ALL lock task features - no exit buttons, no notifications
            dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
            
            // Disable status bar completely
            dpm.setStatusBarDisabled(adminName, true)
            
            // Add all user restrictions to block everything
            dpm.addUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT)
            dpm.addUserRestriction(adminName, "no_adjust_volume")
            dpm.addUserRestriction(adminName, "no_config_notifications")
            dpm.addUserRestriction(adminName, "no_status_bar")
            
            // Set AdScreen as the default Home (Launcher)
            val intentFilter = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            dpm.addPersistentPreferredActivity(
                adminName,
                intentFilter,
                ComponentName(this, MainActivity::class.java)
            )
            
            // Start lock task mode immediately
            startLockTask()
            
            android.util.Log.d("MainActivity", "Lock task mode started. Set as default launcher. Status bar disabled.")
        } else {
            android.util.Log.w("MainActivity", "Not device owner - kiosk features limited")
        }

        // Aggressive Fullscreen / Immersive Blocking
        hideSystemUI()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (ScreenCaptureHelper.handleResult(this, requestCode, resultCode, data, REQUEST_CODE_PROJECTION)) {
            android.util.Log.i("MainActivity", "Screen capture consent obtained")
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars() or WindowInsets.Type.systemGestures())
                // BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE prevents bars from taking focus
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
            // Exclude the entire screen from system gestures
            window.decorView.setOnApplyWindowInsetsListener { view, insets ->
                val gestureInsets = insets.getInsets(WindowInsets.Type.systemGestures())
                // Request to exclude system gesture zones - full screen exclusion
                val exclusionRects = listOf(
                    Rect(0, 0, view.width, view.height) // Entire screen
                )
                view.systemGestureExclusionRects = exclusionRects
                insets
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUI()
        }
    }

    override fun onResume() {
        super.onResume()
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (dpm.isDeviceOwnerApp(packageName)) {
            android.util.Log.d("MainActivity", "Device Owner detected. Ensuring Lock Task is active...")
            val adminName = ComponentName(this, DeviceAdmin::class.java)
            dpm.setLockTaskPackages(adminName, arrayOf(packageName))
            dpm.setStatusBarDisabled(adminName, true)
            dpm.addUserRestriction(adminName, UserManager.DISALLOW_SAFE_BOOT)
            dpm.addUserRestriction(adminName, "no_adjust_volume")
            dpm.addUserRestriction(adminName, "no_config_notifications")
            dpm.addUserRestriction(adminName, "no_status_bar")
            startLockTask()
        } else {
            android.util.Log.d("MainActivity", "Not device owner - kiosk mode limited.")
        }
        hideSystemUI()
    }
}
