package com.example.adscreen.kiosk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.util.Log

/**
 * VolumeEnforcer — Intercepts volume changes and resets to the locked level.
 *
 * When volume lock is active (via "set_volume" command), this receiver
 * listens for android.media.VOLUME_CHANGED_ACTION and immediately resets
 * the media volume to the stored locked value. This prevents users from
 * changing the volume using physical hardware buttons.
 *
 * Register in AndroidManifest.xml:
 *   <receiver android:name=".VolumeEnforcer" android:exported="false">
 *     <intent-filter>
 *       <action android:name="android.media.VOLUME_CHANGED_ACTION" />
 *     </intent-filter>
 *   </receiver>
 *
 * To enable volume lock (from CommandExecutor):
 *   SharedPreferences "adscreen_settings":
 *     - "volume_locked" = true
 *     - "locked_volume" = target volume level (0 to maxVol)
 *
 * To disable volume lock:
 *   Set "volume_locked" = false in SharedPreferences
 */
class VolumeEnforcer : BroadcastReceiver() {

    companion object {
        private const val TAG = "VolumeEnforcer"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != "android.media.VOLUME_CHANGED_ACTION") return

        val prefs = context.getSharedPreferences("adscreen_settings", Context.MODE_PRIVATE)
        val isLocked = prefs.getBoolean("volume_locked", false)
        if (!isLocked) return

        val lockedVolume = prefs.getInt("locked_volume", -1)
        if (lockedVolume < 0) return

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

        if (currentVolume != lockedVolume) {
            // Reset back to the locked volume silently (flag 0 = no UI popup)
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, lockedVolume, 0)
            Log.d(TAG, "🔒 Volume reset: $currentVolume → $lockedVolume (locked)")
        }
    }
}
