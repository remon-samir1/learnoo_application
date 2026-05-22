package com.example.learnoo

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*

/**
 * MainActivity with Extreme Screen Protection implementation for Android
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val SCREEN_PROTECTION_CHANNEL = "com.learnoo.screen_protection"
        private const val SCREEN_PROTECTION_EVENTS_CHANNEL = "com.learnoo.screen_protection/events"
        
        @Volatile
        private var isGlobalProtectionEnabled = true // Enforce global by default as per requirement
        
        @Volatile
        private var localProtectionCount = 0
    }

    private lateinit var methodChannel: MethodChannel
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var displayManager: DisplayManager

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {
            checkScreenRecording()
        }
        override fun onDisplayRemoved(displayId: Int) {
            checkScreenRecording()
        }
        override fun onDisplayChanged(displayId: Int) {
            checkScreenRecording()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enforce FLAG_SECURE immediately
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        
        displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.registerDisplayListener(displayListener, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_PROTECTION_CHANNEL)
        methodChannel.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_PROTECTION_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { eventSink = events }
                override fun onCancel(args: Any?) { eventSink = null }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableGlobalProtection" -> {
                enableGlobalProtection()
                result.success(true)
            }
            "disableGlobalProtection" -> {
                disableGlobalProtection()
                result.success(true)
            }
            "isUsageStatsPermissionGranted" -> {
                result.success(isUsageStatsPermissionGranted())
            }
            "requestUsageStatsPermission" -> {
                requestUsageStatsPermission()
                result.success(true)
            }
            "detectSuspiciousApps" -> {
                result.success(detectSuspiciousApps())
            }
            "isScreenRecording" -> {
                result.success(isScreenRecordingActive())
            }
            "isInMultiWindowMode" -> {
                result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isInMultiWindowMode else false)
            }
            "getProtectionStatus" -> {
                result.success(getProtectionStatus())
            }
            else -> result.notImplemented()
        }
    }

    private fun enableGlobalProtection() {
        runOnUiThread {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            isGlobalProtectionEnabled = true
        }
    }

    private fun disableGlobalProtection() {
        runOnUiThread {
            if (localProtectionCount <= 0) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            isGlobalProtectionEnabled = false
        }
    }

    /**
     * Hybrid detection: Check for external displays / virtual displays
     */
    private fun isScreenRecordingActive(): Boolean {
        val displays = displayManager.displays
        if (displays.size > 1) {
            return true
        }
        for (display in displays) {
            if (display.displayId != android.view.Display.DEFAULT_DISPLAY) {
                return true
            }
        }
        return false
    }

    private fun checkScreenRecording() {
        if (isScreenRecordingActive()) {
            eventSink?.success(mapOf("event" to "recording_started"))
        } else {
            eventSink?.success(mapOf("event" to "recording_stopped"))
        }
    }

    /**
     * UsageStats based detection for suspicious apps
     */
    private fun detectSuspiciousApps(): List<String> {
        if (!isUsageStatsPermissionGranted()) return emptyList()
        
        val suspiciousPackages = listOf(
            "us.zoom.videomeetings", "com.google.android.apps.meetings", 
            "com.microsoft.teams", "com.duapps.recorder", "com.hecorat.screenrecorder.free"
        )
        
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usageStatsManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60, time)
        
        return stats?.filter { it.lastTimeUsed > (time - 1000 * 10) }
                    ?.map { it.packageName }
                    ?.filter { suspiciousPackages.contains(it) }
                    ?: emptyList()
    }

    private fun isUsageStatsPermissionGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        startActivity(intent)
    }

    private fun getProtectionStatus(): Map<String, Any> {
        val hasSecureFlag = (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
        return mapOf(
            "isGlobalEnabled" to isGlobalProtectionEnabled,
            "isSecure" to hasSecureFlag,
            "isRecording" to isScreenRecordingActive(),
            "isMultiWindow" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isInMultiWindowMode else false)
        )
    }

    override fun onResume() {
        super.onResume()
        if (isGlobalProtectionEnabled || localProtectionCount > 0) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onDestroy() {
        displayManager.unregisterDisplayListener(displayListener)
        super.onDestroy()
    }
}
