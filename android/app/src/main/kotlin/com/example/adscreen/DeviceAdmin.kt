package com.example.adscreen

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.UserManager
import android.util.Log
import android.widget.Toast

/**
 * DeviceAdmin — The primary Device Owner receiver for the Adscreen Kiosk.
 * This class is already set as Device Owner on the tablet.
 */
class DeviceAdmin : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "AdscreenDeviceAdmin"

        fun getComponentName(context: Context): ComponentName =
            ComponentName(context, DeviceAdmin::class.java)

        fun getDpm(context: Context): DevicePolicyManager =
            context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "✅ Device Admin enabled")
        Toast.makeText(context, "Device Admin Enabled", Toast.LENGTH_SHORT).show()

        val dpm = getDpm(context)
        val admin = getComponentName(context)

        if (dpm.isDeviceOwnerApp(context.packageName)) {
            Log.i(TAG, "🔒 Device Owner confirmed — applying enterprise policies")

            // Whitelist for Lock Task
            dpm.setLockTaskPackages(admin, arrayOf(context.packageName))

            // Disable status bar & notifications
            dpm.setStatusBarDisabled(admin, true)

            // Core enterprise restrictions
            dpm.addUserRestriction(admin, UserManager.DISALLOW_FACTORY_RESET)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_ADD_USER)
            dpm.addUserRestriction(admin, UserManager.DISALLOW_MOUNT_PHYSICAL_MEDIA)
            dpm.addUserRestriction(admin, "no_unmute_device")
            dpm.addUserRestriction(admin, "no_config_notifications")
            dpm.addUserRestriction(admin, "no_status_bar")
            dpm.addUserRestriction(admin, "no_adjust_volume")

            Log.i(TAG, "✅ Enterprise policies successfully applied")
        }
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "⚠️ Device Admin disabled")
        Toast.makeText(context, "Device Admin Disabled", Toast.LENGTH_SHORT).show()
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        Log.i(TAG, "🚀 Profile provisioning complete")
        val dpm = getDpm(context)
        val admin = getComponentName(context)
        dpm.setProfileEnabled(admin)
        dpm.setProfileName(admin, "Adscreen Kiosk")
    }
}
