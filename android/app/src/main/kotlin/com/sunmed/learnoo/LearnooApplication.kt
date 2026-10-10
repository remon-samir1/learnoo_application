package com.sunmed.learnoo

import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Build

/** Applies to every player in this process, including WebView and SDK players. */
class LearnooApplication : Application() {
    override fun onCreate() {
        // Set before Flutter or any media plugin can create an audio track.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_NONE)
        }
        super.onCreate()
    }
}
