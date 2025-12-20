package com.example.adscreen

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.BatteryManager
import android.os.Looper
import android.widget.Toast
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import retrofit2.Call
import retrofit2.http.Body
import retrofit2.http.POST
import java.util.UUID
import java.util.concurrent.TimeUnit
import android.os.Handler

// 1. Data Model
data class TabletStatus(
   val tablet_id: String,
   val battery_percent: Int,
   val latitude: Double,
   val longitude: Double
)

// 2. API Interface
interface AdscreenApi {
   @POST("api/update_tablet_status")
   fun updateStatus(@Body status: TabletStatus): Call<Void>
}

// 3. Main Service Logic
class TelemetryManager(private val context: Context) {
   private val fusedLocationClient: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)
   private val api: AdscreenApi
   
   // Strict Requirement: Unique Device ID (Persisted for session)
   private val deviceId: String by lazy {
       "REAL_DEVICE_" + UUID.randomUUID().toString().substring(0, 5)
   }

   init {
       val retrofit = retrofit2.Retrofit.Builder()
           .baseUrl(BuildConfig.BASE_URL)
           .addConverterFactory(retrofit2.converter.gson.GsonConverterFactory.create())
           .build()
       api = retrofit.create(AdscreenApi::class.java)
   }
   
   fun startTracking() {
       // Requirement: Use FusedLocationProvider with High Accuracy (GPS preferred, Network fallback)
       val locationRequest = LocationRequest.create().apply {
           interval = TimeUnit.SECONDS.toMillis(60) // Update every 60 seconds
           fastestInterval = TimeUnit.SECONDS.toMillis(30)
           priority = LocationRequest.PRIORITY_HIGH_ACCURACY
       }
       
       val locationCallback = object : LocationCallback() {
           override fun onLocationResult(locationResult: LocationResult) {
               locationResult.lastLocation?.let { location ->
                   sendTelemetry(location)
               }
           }
       }
       
       val hasFine = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
       val hasCoarse = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
       
       if (hasFine || hasCoarse) {
           // Immediate check: Try to get last known location immediately
           fusedLocationClient.lastLocation.addOnSuccessListener { location: Location? ->
               if (location != null) {
                   sendTelemetry(location)
               } else {
                   fireToast("Searching for location...")
               }
           }
           
           // Start periodic updates
           fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.getMainLooper())
       } else {
           fireToast("Location Permission Missing")
       }
   }
   
   private fun sendTelemetry(location: Location) {
       val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
       val batteryLevel = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
       
       // SEND REAL DATA
       val payload = TabletStatus(
           tablet_id = deviceId, 
           battery_percent = batteryLevel,
           latitude = location.latitude,
           longitude = location.longitude
       )
       
       api.updateStatus(payload).enqueue(object : retrofit2.Callback<Void> {
           override fun onResponse(call: Call<Void>, response: retrofit2.Response<Void>) {
               // Strict Requirement: Toast Message "Location Found! Provider: [GPS/Network]"
               // fusedLocationClient usually returns "fused", but sometimes preserves the origin.
               fireToast("Location Found! Provider: ${location.provider}")
               println("SENT: Battery=$batteryLevel%, Lat=${location.latitude}, Lng=${location.longitude}, Prov=${location.provider}")
           }
           override fun onFailure(call: Call<Void>, t: Throwable) {
               fireToast("Network Error: ${t.message}")
           }
       })
   }

   private fun fireToast(msg: String) {
       Handler(Looper.getMainLooper()).post {
           Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
       }
   }
}
