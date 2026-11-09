plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.facialanalysis.facial_analysis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.facialanalysis.facial_analysis"
        // ML Kit Face Mesh Detection needs API 21 or newer; Flutter's own default
        // minimum is already above that, so the framework value is kept.
        minSdk = flutter.minSdkVersion
        // MediaPipe Tasks Vision requires minSdk 28 or higher.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configuring-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release builds are signed with the debug key so `flutter build apk
            // --release` works out of the box for personal installs. Before
            // publishing to a store, replace this with your own signing config;
            // see https://docs.flutter.dev/deployment/android#signing-the-app.
            signingConfig = signingConfigs.getByName("debug")
            // Minification is deliberately OFF: the ML Kit / MediaPipe detector
            // relies on native libraries and reflective glue that R8 can strip,
            // which would fail scans silently. proguard-rules.pro holds the
            // keep rules for the day it is switched on.
            // isMinifyEnabled = true // do not enable without testing on a device
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


