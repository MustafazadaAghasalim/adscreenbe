package com.example.adscreen.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.adscreen.data.Ad
import com.example.adscreen.data.AdsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class PlaylistViewModel @Inject constructor(
    private val repository: AdsRepository
) : ViewModel() {

    private val _ads = MutableStateFlow<List<Ad>>(emptyList())
    val ads: StateFlow<List<Ad>> = _ads.asStateFlow()

    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    init {
        loadAds()
    }

    private fun loadAds() {
        viewModelScope.launch {
            repository.getAdsForDevice().collect { fetchedAds ->
                _ads.value = fetchedAds
                // Reset index if playlist changes to avoid out of bounds, or keep logic if safe
                if (_currentIndex.value >= fetchedAds.size) {
                    _currentIndex.value = 0
                }
            }
        }
    }

    fun onAdFinished() {
        if (_ads.value.isNotEmpty()) {
            _currentIndex.value = (_currentIndex.value + 1) % _ads.value.size
        }
    }
}
