package com.example.adscreen.data

import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.PropertyName

data class Ad(
    @DocumentId val id: String = "",
    @get:PropertyName("imageUrl") val imageUrl: String = "",
    @get:PropertyName("type") val type: String = "image", // 'image' or 'video'
    @get:PropertyName("duration") val duration: Long = 10,
    @get:PropertyName("assignedTablets") val assignedTablets: List<String> = emptyList()
)
