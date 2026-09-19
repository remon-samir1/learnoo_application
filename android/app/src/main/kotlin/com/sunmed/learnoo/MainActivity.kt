package com.sunmed.learnoo

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.Intent
import android.hardware.display.DisplayManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.*

/**
 * MainActivity with Extreme Screen Protection implementation for Android
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val SCREEN_PROTECTION_CHANNEL = "com.learnoo.screen_protection"
        private const val SCREEN_PROTECTION_EVENTS_CHANNEL = "com.learnoo.screen_protection/events"
        private const val DOWNLOADS_CHANNEL = "com.learnoo.downloads"
        private const val DOWNLOADS_FOLDER = "Learnoo"
        
        // Dashboard policy ("Block Screenshots & Recording"), persisted so it
        // applies in onCreate before Dart runs. Defaults to protected.
        private const val PROTECTION_PREFS = "learnoo_screen_protection"
        private const val PROTECTION_PREF_KEY = "global_protection_enabled"

        @Volatile
        private var isGlobalProtectionEnabled = true
        
        @Volatile
        private var localProtectionCount = 0
    }

    /**
     * Debug builds only: skip FLAG_SECURE so the screen can be recorded for
     * the Play Console permission-declaration videos. Release builds are
     * never debuggable, so protection stays enforced for real users.
     */
    private val screenCaptureAllowed: Boolean
        get() = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun applySecureFlag() {
        if (screenCaptureAllowed) return
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
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
        // Restore the last dashboard policy (fail closed: protected when unknown)
        isGlobalProtectionEnabled = getSharedPreferences(PROTECTION_PREFS, Context.MODE_PRIVATE)
            .getBoolean(PROTECTION_PREF_KEY, true)
        // Enforce FLAG_SECURE immediately when required (skipped in debuggable builds)
        if (isGlobalProtectionEnabled || localProtectionCount > 0) {
            applySecureFlag()
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        
        displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        displayManager.registerDisplayListener(displayListener, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_PROTECTION_CHANNEL)
        methodChannel.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> saveToDownloads(call, result)
                    "openDownload" -> openDownload(call, result)
                    else -> result.notImplemented()
                }
            }

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

    /**
     * Copies a finished download into the public Downloads/Learnoo folder so it
     * shows up in the device's file manager, and returns a URI that can open it.
     */
    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath.isNullOrEmpty() || fileName.isNullOrEmpty()) {
            result.error("bad_args", "sourcePath and fileName are required", null)
            return
        }

        Thread {
            try {
                val source = File(sourcePath)
                val saved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(source, fileName, mimeType)
                } else {
                    saveToLegacyDownloads(source, fileName, mimeType)
                }
                runOnUiThread { result.success(saved) }
            } catch (e: Exception) {
                runOnUiThread { result.error("save_failed", e.javaClass.simpleName, null) }
            }
        }.start()
    }

    private fun saveWithMediaStore(source: File, fileName: String, mimeType: String): Map<String, String> {
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + DOWNLOADS_FOLDER)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore insert failed")
        try {
            val output = resolver.openOutputStream(uri) ?: throw IOException("No output stream")
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        // MediaStore renames duplicates ("book (1).pdf"); report the real name.
        var name = fileName
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0) ?: fileName
        }
        return mapOf("uri" to uri.toString(), "name" to name)
    }

    private fun saveToLegacyDownloads(source: File, fileName: String, mimeType: String): Map<String, String> {
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(root, DOWNLOADS_FOLDER)
        if (!dir.exists() && !dir.mkdirs()) throw IOException("Cannot create downloads folder")

        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var target = File(dir, fileName)
        var n = 1
        while (target.exists()) {
            target = File(dir, "$base ($n)$ext")
            n++
        }
        source.copyTo(target)
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mimeType), null)

        val uri = FileProvider.getUriForFile(this, "$packageName.fileProvider", target)
        return mapOf("uri" to uri.toString(), "name" to target.name)
    }

    private fun openDownload(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val mimeType = call.argument<String>("mimeType") ?: "*/*"
        if (uri.isNullOrEmpty()) {
            result.success(false)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.success(false)
        } catch (e: SecurityException) {
            result.success(false)
        }
    }

    private fun persistGlobalProtection(enabled: Boolean) {
        getSharedPreferences(PROTECTION_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(PROTECTION_PREF_KEY, enabled)
            .apply()
    }

    private fun enableGlobalProtection() {
        persistGlobalProtection(true)
        runOnUiThread {
            applySecureFlag()
            isGlobalProtectionEnabled = true
        }
    }

    private fun disableGlobalProtection() {
        persistGlobalProtection(false)
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
            applySecureFlag()
        }
    }

    override fun onDestroy() {
        displayManager.unregisterDisplayListener(displayListener)
        super.onDestroy()
    }
}
