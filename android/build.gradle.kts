// The AppGallery Connect plugin (Huawei Push, settings.gradle.kts) reads the
// Android Gradle Plugin version from the root buildscript classpath and fails
// without it. Same version as in settings.gradle.kts.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // Jitsi Meet SDK artifacts (jitsi_meet_flutter_sdk) are published here,
        // not to Maven Central.
        maven { url = uri("https://github.com/jitsi/jitsi-maven-repository/raw/master/releases") }
        // Huawei Push SDK (huawei_push).
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
