pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Huawei AppGallery Connect Gradle plugin (Huawei Push, see below).
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
    // The AppGallery Connect plugin is published without a Gradle plugin
    // marker, so its id is mapped to the artifact here.
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.huawei.agconnect") {
                useModule("com.huawei.agconnect:agcp:1.9.6.300")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Applied by app/build.gradle.kts only when google-services.json is there.
    id("com.google.gms.google-services") version "4.4.4" apply false
    // Reads app/agconnect-services.json for Huawei Push (phones without
    // Google services).
    id("com.huawei.agconnect") version "1.9.6.300" apply false
}

include(":app")
