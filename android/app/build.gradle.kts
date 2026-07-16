import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.farlo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
        }
    }

    defaultConfig {
        applicationId = "com.farlo.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    // Forces every Firebase native dependency pulled in transitively by the
    // various FlutterFire plugins (firebase_core, firebase_messaging,
    // firebase_crashlytics) onto one consistent, mutually-compatible version
    // set. Without this, each plugin's own internally-pinned version can
    // drift, which is exactly what caused a real crash-on-launch bug found
    // via a Google Play rejection: multiple Firebase Ktx component registrars
    // (Messaging, Crashlytics, Installations) all failed reflection-based
    // instantiation with NoSuchMethodException, because Firebase merged the
    // separate -ktx modules into the main modules in mid-2025 and an
    // unpinned build can end up mixing pre- and post-merge artifact versions.
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
}
