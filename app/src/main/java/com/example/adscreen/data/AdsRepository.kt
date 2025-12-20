package com.example.adscreen.data

import android.provider.Settings
import android.content.Context
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ktx.toObjects
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow

class AdsRepository @Inject constructor(
    private val firestore: FirebaseFirestore,
    @ApplicationContext private val context: Context
) {
    fun getAdsForDevice(): kotlinx.coroutines.flow.Flow<List<Ad>> = kotlinx.coroutines.flow.callbackFlow {
        val deviceId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        Log.d("AdsRepository", "Listening for ads for Device ID: $deviceId")
        
        val registration = firestore.collection("ads")
            .whereArrayContains("assignedTablets", deviceId)
            .addSnapshotListener { snapshot, e ->
                if (e != null) {
                    Log.e("AdsRepository", "Listen failed.", e)
                    close(e)
                    return@addSnapshotListener
                }
                
                val ads = snapshot?.toObjects<Ad>() ?: emptyList()
                Log.d("AdsRepository", "Ads updated: ${ads.size} ads")
                trySend(ads)
            }
            
        awaitClose { registration.remove() }
    }
}
