package com.example.adscreen.kiosk

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.concurrent.TimeUnit

/**
 * SilentInstaller — Downloads and installs APK updates silently without user interaction.
 *
 * STRATEGY:
 *   Device Owner apps can use PackageInstaller.Session with a privileged session
 *   to install APKs without any system UI or user confirmation dialogs.
 *
 * FLOW:
 *   1. Server sends WebSocket command: { "command": "update_apk", "payload": { "url": "...", "version": "..." } }
 *   2. CommandExecutor calls SilentInstaller.downloadAndInstall(url, versionCode)
 *   3. APK is downloaded to internal storage
 *   4. PackageInstaller session is created and committed
 *   5. InstallResultReceiver handles success/failure
 *   6. On success: the app restarts automatically (Android recreates the process)
 *   7. On failure: error is reported back to server via WebSocket ACK
 *
 * REQUIREMENTS:
 *   - Device Owner status (verified before install)
 *   - Network connectivity
 *   - Sufficient storage space
 *
 * SAFETY FEATURES:
 *   - Version check: will not downgrade unless forced
 *   - SHA-256 checksum verification (if provided)
 *   - Download retry with exponential backoff
 *   - Partial download cleanup on failure
 *   - Rollback notification to server on install failure
 */
class SilentInstaller(
    private val context: Context,
    private val scope: CoroutineScope,
    private val onResult: (success: Boolean, message: String) -> Unit
) {
    companion object {
        private const val TAG = "SilentInstaller"
        private const val APK_DIR = "apk_updates"
        private const val INSTALL_ACTION = "com.adscreen.kiosk.INSTALL_RESULT"
        private const val MAX_RETRIES = 3
        private const val DOWNLOAD_TIMEOUT_SEC = 300L // 5 minutes for large APKs
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(DOWNLOAD_TIMEOUT_SEC, TimeUnit.SECONDS)
        .build()

    private val dpm: DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    /**
     * Download an APK from [url] and install it silently.
     *
     * @param url        Direct download URL for the APK file
     * @param versionCode Expected version code (for verification, 0 = skip check)
     * @param sha256      Expected SHA-256 hex string (null = skip check)
     * @param force       If true, allow downgrade
     */
    fun downloadAndInstall(
        url: String,
        versionCode: Long = 0,
        sha256: String? = null,
        force: Boolean = false
    ) {
        if (!dpm.isDeviceOwnerApp(context.packageName)) {
            onResult(false, "Not Device Owner — cannot silent-install")
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                Log.i(TAG, "📦 Starting silent APK update from: $url")

                // ── 1. Download APK ──
                val apkFile = downloadApk(url) ?: run {
                    onResult(false, "Download failed after $MAX_RETRIES retries")
                    return@launch
                }

                // ── 2. Verify SHA-256 if provided ──
                if (sha256 != null) {
                    val actualHash = computeSha256(apkFile)
                    if (!actualHash.equals(sha256, ignoreCase = true)) {
                        apkFile.delete()
                        onResult(false, "Checksum mismatch: expected=$sha256 actual=$actualHash")
                        return@launch
                    }
                    Log.i(TAG, "✅ SHA-256 verified")
                }

                // ── 3. Version check ──
                if (versionCode > 0 && !force) {
                    val currentVersion = getCurrentVersionCode()
                    if (versionCode <= currentVersion) {
                        apkFile.delete()
                        onResult(false, "Version $versionCode <= current $currentVersion (use force=true to downgrade)")
                        return@launch
                    }
                }

                // ── 4. Install silently ──
                installApk(apkFile)

            } catch (e: Exception) {
                Log.e(TAG, "Silent install failed", e)
                onResult(false, "Install error: ${e.message}")
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Download
    // ═══════════════════════════════════════════════════════════════════

    private fun downloadApk(url: String): File? {
        val dir = File(context.filesDir, APK_DIR).apply { mkdirs() }
        val apkFile = File(dir, "update_${System.currentTimeMillis()}.apk")

        for (attempt in 1..MAX_RETRIES) {
            try {
                Log.i(TAG, "⬇️ Download attempt $attempt/$MAX_RETRIES")

                val request = Request.Builder().url(url).build()
                httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        Log.e(TAG, "HTTP ${response.code}: ${response.message}")
                        if (attempt == MAX_RETRIES) return null
                        Thread.sleep(attempt * 5000L) // Backoff
                        return@use
                    }

                    val body = response.body ?: run {
                        Log.e(TAG, "Empty response body")
                        return null
                    }

                    val totalBytes = body.contentLength()
                    var downloadedBytes = 0L

                    FileOutputStream(apkFile).use { fos ->
                        body.byteStream().use { input ->
                            val buffer = ByteArray(8192)
                            var bytesRead: Int
                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                fos.write(buffer, 0, bytesRead)
                                downloadedBytes += bytesRead
                                if (totalBytes > 0) {
                                    val percent = (downloadedBytes * 100 / totalBytes).toInt()
                                    if (percent % 20 == 0) {
                                        Log.d(TAG, "⬇️ Download: $percent%")
                                    }
                                }
                            }
                        }
                    }

                    Log.i(TAG, "✅ Downloaded ${apkFile.length() / 1024}KB → ${apkFile.absolutePath}")
                    return apkFile
                }
            } catch (e: Exception) {
                Log.e(TAG, "Download attempt $attempt failed", e)
                if (attempt == MAX_RETRIES) {
                    apkFile.delete()
                    return null
                }
                Thread.sleep(attempt * 5000L)
            }
        }
        return null
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Silent Install via PackageInstaller
    // ═══════════════════════════════════════════════════════════════════

    private fun installApk(apkFile: File) {
        Log.i(TAG, "📲 Starting silent install: ${apkFile.name} (${apkFile.length() / 1024}KB)")

        val packageInstaller = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            // For Device Owner, the install is automatically privileged
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }

        var sessionId = -1
        try {
            sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            // Write APK to session
            session.openWrite("adscreen_update.apk", 0, apkFile.length()).use { sessionStream ->
                apkFile.inputStream().use { apkStream ->
                    apkStream.copyTo(sessionStream, 65536)
                }
                session.fsync(sessionStream)
            }

            // Create status receiver
            val intent = Intent(INSTALL_ACTION).apply {
                setPackage(context.packageName)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                sessionId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            // Register receiver for result
            registerInstallReceiver()

            // Commit — this triggers the actual install
            session.commit(pendingIntent.intentSender)
            Log.i(TAG, "📲 Install session committed (id=$sessionId)")

        } catch (e: Exception) {
            Log.e(TAG, "Install session failed", e)
            if (sessionId != -1) {
                try { packageInstaller.abandonSession(sessionId) } catch (_: Exception) {}
            }
            onResult(false, "Install session error: ${e.message}")
        } finally {
            // Cleanup APK file after a delay (install may still be reading it)
            scope.launch {
                delay(60_000)
                apkFile.delete()
                Log.d(TAG, "🗑️ Cleaned up APK file")
            }
        }
    }

    private fun registerInstallReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val status = intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE
                )
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""

                when (status) {
                    PackageInstaller.STATUS_SUCCESS -> {
                        Log.i(TAG, "✅ APK installed successfully — app will restart")
                        onResult(true, "Install successful")
                    }
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        // This should NOT happen for Device Owner, but handle it
                        Log.w(TAG, "⚠️ User action required (not Device Owner?)")
                        val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        confirmIntent?.let {
                            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            ctx.startActivity(it)
                        }
                    }
                    else -> {
                        Log.e(TAG, "❌ Install failed: status=$status message=$message")
                        onResult(false, "Install failed: $message (status=$status)")
                    }
                }

                try { ctx.unregisterReceiver(this) } catch (_: Exception) {}
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                receiver,
                IntentFilter(INSTALL_ACTION),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            context.registerReceiver(receiver, IntentFilter(INSTALL_ACTION))
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Utilities
    // ═══════════════════════════════════════════════════════════════════

    private fun getCurrentVersionCode(): Long {
        return try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        } catch (e: Exception) {
            0L
        }
    }

    private fun computeSha256(file: File): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            while (stream.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Cleanup old APK files (call periodically from KioskForegroundService)
     */
    fun cleanupOldApks() {
        val dir = File(context.filesDir, APK_DIR)
        if (!dir.exists()) return
        dir.listFiles()?.forEach { file ->
            if (System.currentTimeMillis() - file.lastModified() > 24 * 60 * 60 * 1000) {
                file.delete()
                Log.d(TAG, "🗑️ Cleaned old APK: ${file.name}")
            }
        }
    }
}
