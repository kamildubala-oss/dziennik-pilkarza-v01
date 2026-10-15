import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Wtyczka Flutter Gradle musi być zastosowana po wtyczkach Android i Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.emergent.mlodypilkarz.dziennik_pilkarza"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.emergent.mlodypilkarz.dziennik_pilkarza"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Podpis kluczem debug - wystarczy do instalacji ręcznej APK.
            // Dla Google Play skonfiguruj własny keystore.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider - udostępnianie eksportowanych plików.
    implementation("androidx.core:core:1.13.1")
}
