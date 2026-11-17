package com.sunmed.learnoo

import android.content.Context
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.huawei.hms.api.HuaweiApiAvailability
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Which push service this phone has, for PushService (Dart).
 *
 * `fcm` when Google Play services work (every Google phone, and Huawei phones
 * that still have Google services); `hms` on phones that have only Huawei
 * Mobile Services (Huawei phones sold since 2019); otherwise `fcm`, as before.
 */
object PushProviderChannel {
    private const val CHANNEL = "com.learnoo.push_provider"

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "provider" -> result.success(provider(appContext))
                else -> result.notImplemented()
            }
        }
    }

    private fun provider(context: Context): String {
        val google = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        if (google) return "fcm"
        val huawei = HuaweiApiAvailability.getInstance()
            .isHuaweiMobileServicesAvailable(context) == com.huawei.hms.api.ConnectionResult.SUCCESS
        return if (huawei) "hms" else "fcm"
    }
}
