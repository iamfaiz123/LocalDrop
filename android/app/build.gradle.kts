import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.localdrop.localdrop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.localdrop.localdrop"
        // API 24+: getifaddrs() for host IP detection and the photo picker backport.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // AdMob app id: pass -PadmobAppId=ca-app-pub-XXXX~YYYY for production builds.
        manifestPlaceholders["admobAppId"] =
            (project.findProperty("admobAppId") as String?) ?: "ca-app-pub-3940256099942544~3347511713"
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release signing: provide android/key.properties (see docs/BUILD.md).
            // Falls back to debug keys so `flutter run --release` works locally.
            val keyProps = rootProject.file("key.properties")
            signingConfig = if (keyProps.exists()) {
                val p = Properties().apply { keyProps.inputStream().use { load(it) } }
                signingConfigs.create("release") {
                    storeFile = file(p.getProperty("storeFile"))
                    storePassword = p.getProperty("storePassword")
                    keyAlias = p.getProperty("keyAlias")
                    keyPassword = p.getProperty("keyPassword")
                }
            } else {
                signingConfigs.getByName("debug")
            }
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
    // NotificationCompat / ServiceCompat for the hosting foreground service.
    implementation("androidx.core:core-ktx:1.13.1")
}
