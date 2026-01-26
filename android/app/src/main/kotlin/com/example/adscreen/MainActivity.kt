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
import android.view.View
import android.view.WindowManager
import android.os.Build
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.os.UserManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.adscreen.kiosk/telemetry"
    private var isKioskDesired = true // Default to true

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        if (isKioskDesired) {
            val keyCode = event.keyCode
            if (keyCode == android.view.KeyEvent.KEYCODE_VOLUME_UP || 
                keyCode == android.view.KeyEvent.KEYCODE_VOLUME_DOWN) {
                return true // Consume the event
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminName = ComponentName(this, DeviceAdmin::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Brightness not available.", null)
                    }
                }
                "setScreenBrightness" -> {
                    val brightness = call.argument<Double>("brightness") ?: 0.5
                    try {
                        val lp = window.attributes
                        lp.screenBrightness = brightness.toFloat()
                        window.attributes = lp
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "startKiosk" -> {
                    isKioskDesired = true
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
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Error in stopKiosk: ${e.message}")
                        result.error("ERROR", e.message, null)
                    }
                }
                "exitToHome" -> {
                    try {
                        val intent = Intent(Intent.ACTION_MAIN)
                        intent.addCategory(Intent.CATEGORY_HOME)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to exit to home: ${e.message}", null)
                    }
                }
                "killApp" -> {
                    try {
                        // Success: Ensure all restrictions are definitely cleared natively before dying
                        if (dpm.isDeviceOwnerApp(packageName)) {
                            dpm.setStatusBarDisabled(adminName, false)
                            dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS)
                        }
                        
                        // Reliability: Finish and remove from recents
                        finishAndRemoveTask()
                        
                        // Force process death after a tiny sliver of time to allow activity to clear
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                            android.util.Log.d("MainActivity", "Force killing process now...")
                            android.os.Process.killProcess(android.os.Process.myPid())
                            System.exit(0)
                        }, 50)
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to kill app: ${e.message}", null)
                    }
                }
                "rebootDevice" -> {
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        try {
                            dpm.reboot(adminName)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_OWNER", "Not device owner", null)
                    }
                }
                "shutdownDevice" -> {
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        try {
                            // Attempting shutdown via intent first as DPM doesn't have direct shutdown
                            val intent = Intent("com.android.internal.intent.action.REQUEST_SHUTDOWN")
                            intent.putExtra("android.intent.extra.KEY_CONFIRM", false)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to reboot if shutdown intent fails
                            try {
                                dpm.reboot(adminName)
                                result.success(true)
                            } catch (re: Exception) {
                                result.error("ERROR", re.message, null)
                            }
                        }
                    } else {
                        result.error("NOT_OWNER", "Not device owner", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminName = ComponentName(this, DeviceAdmin::class.java)
        
        if (dpm.isDeviceOwnerApp(packageName)) {
            dpm.setLockTaskPackages(adminName, arrayOf(packageName))
            dpm.setLockTaskFeatures(adminName, DevicePolicyManager.LOCK_TASK_FEATURE_NONE)
            if (isKioskDesired) {
                dpm.setStatusBarDisabled(adminName, true)
                dpm.addUserRestriction(adminName, "no_adjust_volume")
                // Ensure we are in lock task mode
                startLockTask()
            }
        }

        // Aggressive Fullscreen / Immersive Blocking
        hideSystemUI()
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                // Stricter behavior: BEHAVIOR_SHOW_BARS_BY_TOUCH is even less prone to accidental swipes
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_BARS_BY_TOUCH
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
        if (dpm.isDeviceOwnerApp(packageName) && isKioskDesired) {
            android.util.Log.d("MainActivity", "Device Owner detected. Ensuring Lock Task is active...")
            val adminName = ComponentName(this, DeviceAdmin::class.java)
            dpm.setLockTaskPackages(adminName, arrayOf(packageName))
            dpm.addUserRestriction(adminName, "no_adjust_volume")
            startLockTask()
        } else {
            android.util.Log.d("MainActivity", "Kiosk mode not desired or not owner.")
        }
    }
}
