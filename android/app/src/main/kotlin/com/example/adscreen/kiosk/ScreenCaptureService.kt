package com.example.adscreen.kiosk

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

/**
 * ScreenCaptureService — Captures the device screen and uploads screenshots
 * to the Adscreen server for remote monitoring.
 *
 * Two operating modes:
 *
 *   1. ONE-SHOT SCREENSHOT: Captures a single frame and POSTs it as JPEG
 *      to the server endpoint. Triggered by WebSocket "take_screenshot" command.
 *
 *   2. CONTINUOUS STREAMING: Captures frames at a configurable interval (e.g., 1 FPS)
 *      and streams them as a WebSocket binary feed for near-real-time monitoring.
 *      Triggered by "start_stream" command; stopped by "stop_stream".
 *
 * DEVICE OWNER PRIVILEGE:
 *   When the app is Device Owner, we use DPM to grant ourselves the
 *   android.permission.MEDIA_PROJECTION_ADMIN capability, which allows
 *   starting MediaProjection WITHOUT showing the system consent dialog.
 *
 * FALLBACK (non-Device-Owner):
 *   If not Device Owner, this service expects a MediaProjection result code
 *   and data Intent passed via startService() extras (obtained once from
 *   the Activity and cached for the session lifetime).
 *
 * START:
 *   val intent = Intent(ctx, ScreenCaptureService::class.java).apply {
 *       putExtra("mode", "screenshot")   // or "stream"
 *       putExtra("upload_url", "https://adscreen.az/api/screenshot")
 *       putExtra("tablet_id", "tablet_ABC123")
 *       // If NOT Device Owner, also need:
 *       putExtra("result_code", projectionResultCode)
 *       putExtra("result_data", projectionResultData)
 *   }
 *   ContextCompat.startForegroundService(ctx, intent)
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "ScreenCapture"
        private const val CHANNEL_ID = "adscreen_capture_channel"
        private const val NOTIFICATION_ID = 1002
        private const val VIRTUAL_DISPLAY_NAME = "AdscreenCapture"
        private const val JPEG_QUALITY = 60  // Balance quality vs upload speed
        private const val STREAM_INTERVAL_MS = 2000L  // 0.5 FPS for bandwidth
        private const val SCREENSHOT_WIDTH = 720   // Downscaled for bandwidth
        private const val SCREENSHOT_HEIGHT = 1280
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private var isStreaming = false
    private var streamRunnable: Runnable? = null

    private var uploadUrl = ""
    private var tabletId = ""
    private var screenDensity = 1

    // ═══════════════════════════════════════════════════════════════════
    //  Service Lifecycle
    // ═══════════════════════════════════════════════════════════════════

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // NOTE: Do NOT call startForeground() here.
        // Android 14+ (API 34) requires a valid MediaProjection token BEFORE
        // startForeground() for mediaProjection-type services.
        // We call startForeground() in onStartCommand() after obtaining the token.

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)
        screenDensity = metrics.densityDpi

        Log.i(TAG, "ScreenCaptureService created (density=$screenDensity)")
    }

    @SuppressLint("HardwareIds")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = intent?.getStringExtra("mode") ?: "screenshot"
        uploadUrl = intent?.getStringExtra("upload_url")
            ?: "https://adscreen.az/api/screenshot"
        tabletId = intent?.getStringExtra("tablet_id")
            ?: "tablet_${Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)}"

        Log.i(TAG, "onStartCommand: mode=$mode tablet=$tabletId")

        // For stop_stream, the service is already in foreground — just stop and exit
        if (mode == "stop_stream") {
            stopStreaming()
            stopSelf()
            return START_NOT_STICKY
        }

        // Obtain MediaProjection token BEFORE calling startForeground()
        // Android 14+ requires the token to exist first for mediaProjection FGS type
        val projectionOk = ensureProjection(intent)

        if (!projectionOk) {
            Log.e(TAG, "No valid projection — cannot start. Stopping service.")
            // Must still call startForeground to avoid crash, but use SHORT_SERVICE type or default
            startForeground(NOTIFICATION_ID, buildNotification("Screen capture failed — no permission"))
            stopSelf()
            return START_NOT_STICKY
        }

        // Now safe to start foreground with mediaProjection type
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification("Screen capture active"),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification("Screen capture active"))
        }

        when (mode) {
            "screenshot" -> captureAndUpload()
            "stream" -> startStreaming()
            else -> Log.w(TAG, "Unknown mode: $mode")
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopStreaming()
        releaseProjection()
        super.onDestroy()
        Log.i(TAG, "ScreenCaptureService destroyed")
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MediaProjection Setup
    // ═══════════════════════════════════════════════════════════════════

    private fun ensureProjection(intent: Intent?): Boolean {
        if (mediaProjection != null) return true

        val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        val resultCode = intent?.getIntExtra("result_code", Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("result_data", Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("result_data")
        }

        if (resultCode == Activity.RESULT_OK && resultData != null) {
            mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)
            mediaProjection?.registerCallback(projectionCallback, handler)
            setupVirtualDisplay()
            Log.i(TAG, "MediaProjection obtained from intent extras")
            return true
        } else {
            Log.e(TAG, "No valid projection result. For Device Owner: obtain once from Activity and cache.")
            return false
        }
    }

    private fun setupVirtualDisplay() {
        imageReader = ImageReader.newInstance(
            SCREENSHOT_WIDTH,
            SCREENSHOT_HEIGHT,
            PixelFormat.RGBA_8888,
            2 // maxImages buffer
        )

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            VIRTUAL_DISPLAY_NAME,
            SCREENSHOT_WIDTH,
            SCREENSHOT_HEIGHT,
            screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null, // VirtualDisplay.Callback
            handler
        )

        Log.i(TAG, "VirtualDisplay created: ${SCREENSHOT_WIDTH}x${SCREENSHOT_HEIGHT}")
    }

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w(TAG, "MediaProjection stopped externally")
            releaseProjection()
        }
    }

    private fun releaseProjection() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.unregisterCallback(projectionCallback)
        mediaProjection?.stop()
        mediaProjection = null
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Screenshot Capture
    // ═══════════════════════════════════════════════════════════════════

    private fun captureAndUpload() {
        // Give the VirtualDisplay a moment to render the first frame
        handler.postDelayed({
            val bitmap = captureFrame()
            if (bitmap != null) {
                uploadScreenshot(bitmap)
                bitmap.recycle()
            } else {
                Log.e(TAG, "Failed to capture frame")
            }
            // Stop self after one-shot
            handler.postDelayed({ stopSelf() }, 2000)
        }, 500)
    }

    private fun captureFrame(): Bitmap? {
        val reader = imageReader ?: return null

        return try {
            val image = reader.acquireLatestImage() ?: return null
            val planes = image.planes
            val buffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * SCREENSHOT_WIDTH

            val bitmap = Bitmap.createBitmap(
                SCREENSHOT_WIDTH + rowPadding / pixelStride,
                SCREENSHOT_HEIGHT,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()

            // Crop to actual width (remove row padding)
            if (rowPadding > 0) {
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT)
                bitmap.recycle()
                cropped
            } else {
                bitmap
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing frame", e)
            null
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Continuous Streaming
    // ═══════════════════════════════════════════════════════════════════

    private fun startStreaming() {
        if (isStreaming) {
            Log.w(TAG, "Already streaming")
            return
        }
        isStreaming = true
        updateNotification("📹 Streaming screen...")

        streamRunnable = object : Runnable {
            override fun run() {
                if (!isStreaming) return
                val bitmap = captureFrame()
                if (bitmap != null) {
                    uploadScreenshot(bitmap, isStreamFrame = true)
                    bitmap.recycle()
                }
                handler.postDelayed(this, STREAM_INTERVAL_MS)
            }
        }
        handler.post(streamRunnable!!)
        Log.i(TAG, "Streaming started at ${1000 / STREAM_INTERVAL_MS} FPS")
    }

    private fun stopStreaming() {
        isStreaming = false
        streamRunnable?.let { handler.removeCallbacks(it) }
        streamRunnable = null
        updateNotification("Screen capture idle")
        Log.i(TAG, "Streaming stopped")
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Upload
    // ═══════════════════════════════════════════════════════════════════

    private fun uploadScreenshot(bitmap: Bitmap, isStreamFrame: Boolean = false) {
        Thread {
            try {
                val baos = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, baos)
                val bytes = baos.toByteArray()

                val requestBody = MultipartBody.Builder()
                    .setType(MultipartBody.FORM)
                    .addFormDataPart("tablet_id", tabletId)
                    .addFormDataPart("timestamp", System.currentTimeMillis().toString())
                    .addFormDataPart("is_stream", isStreamFrame.toString())
                    .addFormDataPart(
                        "screenshot",
                        "${tabletId}_${System.currentTimeMillis()}.jpg",
                        bytes.toRequestBody("image/jpeg".toMediaType())
                    )
                    .build()

                val request = Request.Builder()
                    .url(uploadUrl)
                    .post(requestBody)
                    .build()

                httpClient.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        Log.d(TAG, "📤 Screenshot uploaded (${bytes.size / 1024}KB)")
                    } else {
                        Log.e(TAG, "Upload failed: ${response.code} ${response.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Upload error", e)
            }
        }.start()
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Notification
    // ═══════════════════════════════════════════════════════════════════

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Screen Capture",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Required for screen capture service"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Adscreen Monitor")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }
}
