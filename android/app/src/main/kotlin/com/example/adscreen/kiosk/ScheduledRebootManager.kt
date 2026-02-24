package com.example.adscreen.kiosk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.adscreen.DeviceAdmin
import java.util.Calendar

/**
 * ScheduledRebootManager — Uses AlarmManager to trigger a daily reboot
 * at a configured time (e.g., "04:00").
 *
 * The reboot is executed via DevicePolicyManager.reboot() which requires
 * the app to be Device Owner.
 *
 * Usage:
 *   ScheduledRebootManager.schedule(context, "04:00")
 *
 * Cancel:
 *   ScheduledRebootManager.cancel(context)
 */
object ScheduledRebootManager {
    private const val TAG = "ScheduledReboot"
    private const val REQUEST_CODE = 9001

    /**
     * Schedule a daily reboot at the given time (HH:MM format).
     * If the time has already passed today, schedules for tomorrow.
     * Uses setRepeating with INTERVAL_DAY for daily recurrence.
     */
    fun schedule(context: Context, time: String) {
        val parts = time.split(":")
        if (parts.size != 2) {
            Log.e(TAG, "Invalid time format: $time (expected HH:MM)")
            return
        }

        val hour = parts[0].toIntOrNull() ?: return
        val minute = parts[1].toIntOrNull() ?: return

        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            // If the time already passed today, schedule for tomorrow
            if (before(Calendar.getInstance())) {
                add(Calendar.DAY_OF_MONTH, 1)
            }
        }

        val intent = Intent(context, RebootReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            calendar.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )
        Log.i(TAG, "⏰ Daily reboot alarm set for $time (next: ${calendar.time})")
    }

    /**
     * Cancel any scheduled daily reboot.
     */
    fun cancel(context: Context) {
        val intent = Intent(context, RebootReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        Log.i(TAG, "⏰ Daily reboot alarm cancelled")
    }
}

/**
 * RebootReceiver — Triggered by AlarmManager at the scheduled reboot time.
 * Executes the reboot only if the app is Device Owner.
 *
 * Register in AndroidManifest.xml:
 *   <receiver android:name=".RebootReceiver" android:exported="false" />
 */
class RebootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.i("RebootReceiver", "⏰ Scheduled reboot alarm fired")

        val dpm = DeviceAdmin.getDpm(context)
        val admin = DeviceAdmin.getComponentName(context)

        if (dpm.isDeviceOwnerApp(context.packageName)) {
            Log.w("RebootReceiver", "⚡ Executing scheduled reboot NOW")
            dpm.reboot(admin)
        } else {
            Log.e("RebootReceiver", "Cannot reboot — not Device Owner")
        }
    }
}
