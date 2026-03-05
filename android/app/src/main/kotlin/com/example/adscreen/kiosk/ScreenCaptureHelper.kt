package com.example.adscreen.kiosk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.util.Log

/**
 * ScreenCaptureHelper — Manages MediaProjection consent and caching.
 *
 * On Device Owner tablets, the first projection consent is obtained automatically
 * during provisioning. The result code + data Intent are cached in SharedPrefs
 * so subsequent screenshot/stream requests don't need user interaction.
 *
 * USAGE IN MAINACTIVITY:
 *
 *   // In configureFlutterEngine, handle "requestScreenCapture":
 *   ScreenCaptureHelper.requestProjection(this, REQUEST_CODE_PROJECTION)
 *
 *   // In onActivityResult:
 *   ScreenCaptureHelper.handleResult(this, requestCode, resultCode, data)
 *
 *   // To take a screenshot (from MethodChannel or WebSocket command):
 *   ScreenCaptureHelper.takeScreenshot(context, uploadUrl, tabletId)
 *
 *   // To start live stream:
 *   ScreenCaptureHelper.startStream(context, uploadUrl, tabletId)
 */
object ScreenCaptureHelper {
    private const val TAG = "ScreenCaptureHelper"
    private const val PREFS_NAME = "screen_capture_prefs"
    private const val KEY_RESULT_CODE = "projection_result_code"
    private const val KEY_HAS_CONSENT = "has_projection_consent"

    // In-memory cache for the projection data Intent (cannot serialize Binder)
    private var cachedResultCode: Int = Activity.RESULT_CANCELED
    private var cachedResultData: Intent? = null

    /**
     * Request MediaProjection consent from the system.
     * This shows the "Start recording?" dialog exactly ONCE.
     */
    fun requestProjection(activity: Activity, requestCode: Int) {
        val projectionManager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = projectionManager.createScreenCaptureIntent()
        activity.startActivityForResult(intent, requestCode)
        Log.i(TAG, "Projection consent requested")
    }

    /**
     * Handle the consent result and cache it for future use.
     */
    fun handleResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?, expectedRequestCode: Int): Boolean {
        if (requestCode != expectedRequestCode) return false

        if (resultCode == Activity.RESULT_OK && data != null) {
            cachedResultCode = resultCode
            cachedResultData = data

            // Mark that we have consent
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_RESULT_CODE, resultCode)
                .putBoolean(KEY_HAS_CONSENT, true)
                .apply()

            Log.i(TAG, "✅ Projection consent granted and cached")
            return true
        } else {
            Log.w(TAG, "⚠️ Projection consent denied (resultCode=$resultCode)")
            return false
        }
    }

    /**
     * Check if we have cached projection consent.
     */
    fun hasConsent(context: Context): Boolean {
        if (cachedResultData != null) return true
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HAS_CONSENT, false)
    }

    /**
     * Take a one-shot screenshot and upload.
     */
    fun takeScreenshot(context: Context, uploadUrl: String, tabletId: String) {
        if (cachedResultData == null) {
            Log.e(TAG, "No projection consent cached — cannot take screenshot")
            return
        }

        val intent = Intent(context, ScreenCaptureService::class.java).apply {
            putExtra("mode", "screenshot")
            putExtra("upload_url", uploadUrl)
            putExtra("tablet_id", tabletId)
            putExtra("result_code", cachedResultCode)
            putExtra("result_data", cachedResultData)
        }
        androidx.core.content.ContextCompat.startForegroundService(context, intent)
    }

    /**
     * Start continuous screen streaming.
     */
    fun startStream(context: Context, uploadUrl: String, tabletId: String) {
        if (cachedResultData == null) {
            Log.e(TAG, "No projection consent cached — cannot stream")
            return
        }

        val intent = Intent(context, ScreenCaptureService::class.java).apply {
            putExtra("mode", "stream")
            putExtra("upload_url", uploadUrl)
            putExtra("tablet_id", tabletId)
            putExtra("result_code", cachedResultCode)
            putExtra("result_data", cachedResultData)
        }
        androidx.core.content.ContextCompat.startForegroundService(context, intent)
    }

    /**
     * Stop the screen stream.
     */
    fun stopStream(context: Context) {
        val intent = Intent(context, ScreenCaptureService::class.java).apply {
            putExtra("mode", "stop_stream")
        }
        context.startService(intent)
    }
}
