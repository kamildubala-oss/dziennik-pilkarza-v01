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

    testBuildType = if (project.hasProperty("startupSmoke")) "release" else "debug"

    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        applicationId = "com.emergent.mlodypilkarz.dziennik_pilkarza"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (project.hasProperty("startupSmoke")) {
                proguardFiles("startup-test.pro")
            }
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
    // Instrumentowana aplikacja release oraz jej test muszą rozwiązać te
    // same wersje bibliotek runnera. Zwykły APK nie dostaje tych zależności.
    if (project.hasProperty("startupSmoke")) {
        implementation("androidx.test:runner:1.6.2")
        implementation("androidx.test:rules:1.6.1")
        implementation("junit:junit:4.13.2")
    }
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("junit:junit:4.13.2")
    // FileProvider - udostępnianie eksportowanych plików.
    implementation("androidx.core:core:1.13.1")
}
