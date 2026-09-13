import java.util.Properties
import java.io.FileInputStream
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
android {
    namespace = "com.example.learnoo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }
     signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.learnoo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Jitsi Meet SDK 13.x requires API 26 or newer.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            // signingConfig = signingConfigs.getByName("debug")
               signingConfig = signingConfigs.getByName("debug")
            signingConfig = signingConfigs.getByName("release")
        }
    }

    lint {
        disable += "Instantiatable"
    }

    packaging {
        jniLibs {
            // The Jitsi Meet SDK (react-android) and flutter_pdfview (pdfium)
            // each bundle the shared C++ runtime. It is the same library, so
            // taking the first one is correct — without this the native-lib
            // merge fails on a duplicate path.
            pickFirsts += "lib/**/libc++_shared.so"
        }
    }
}

// The Jitsi Meet SDK ships its own copy of the media3 RTSP classes inside
// react-native-video. video_player_android pulls the standalone
// `media3-exoplayer-rtsp` artifact in transitively, and having both makes
// `checkDuplicateClasses` fail. Chapter video is HLS/MP4 — the app never plays
// RTSP — so the standalone artifact is dropped and Jitsi's copy is used.
configurations.all {
    exclude(group = "androidx.media3", module = "media3-exoplayer-rtsp")
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // ExoPlayer media3 dependencies for better video playback on all devices including OPPO/ColorOS
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.4.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.4.1")
    implementation("androidx.media3:media3-session:1.4.1")
    // media3-exoplayer-rtsp is deliberately absent: the Jitsi Meet SDK bundles
    // the same RTSP classes through react-native-video, and having both makes
    // the duplicate-class check fail. Chapter video is HLS/MP4, never RTSP.
}
