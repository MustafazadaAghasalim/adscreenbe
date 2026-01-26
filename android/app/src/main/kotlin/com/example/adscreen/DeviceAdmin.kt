package com.example.adscreen

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.os.UserManager

class DeviceAdmin : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminName = ComponentName(context, DeviceAdmin::class.java)
        if (dpm.isDeviceOwnerApp(context.packageName)) {
            dpm.setLockTaskPackages(adminName, arrayOf(context.packageName))
            // This is the key to blocking swipe-down / status bar
            dpm.setStatusBarDisabled(adminName, true)
            
            // Block notifications and system changes (using string literals to avoid unresolved reference)
            dpm.addUserRestriction(adminName, "no_config_notifications")
            dpm.addUserRestriction(adminName, "no_status_bar")
        }
        Toast.makeText(context, "Device Admin Enabled", Toast.LENGTH_SHORT).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Toast.makeText(context, "Device Admin Disabled", Toast.LENGTH_SHORT).show()
    }
}
