plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val requireReleaseSigning = System.getenv("REQUIRE_RELEASE_SIGNING") == "true"
if (requireReleaseSigning && releaseKeystore.isNullOrBlank()) {
    error("Release CI requires ANDROID_KEYSTORE_PATH and signing credentials.")
}

// Each channel is its own Android app (package name + launcher label), so
// production, beta and local debug builds install side by side. With one
// shared package Android refuses a build signed by another key (debug vs.
// release) or with a lower versionCode (switching from beta back to
// production) and the user has to uninstall, losing quizzes and settings.
val releaseChannel = System.getenv("QUIZMO_RELEASE_CHANNEL")?.trim().orEmpty()
if (releaseChannel !in setOf("", "production", "beta")) {
    error("QUIZMO_RELEASE_CHANNEL must be 'production' or 'beta', got '$releaseChannel'.")
}
val isBetaChannel = releaseChannel == "beta"

android {
    namespace = "com.quizapp.quizmo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.quizapp.quizmo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (isBetaChannel) {
            applicationIdSuffix = ".beta"
            manifestPlaceholders["appLabel"] = "quizmo beta"
        } else {
            manifestPlaceholders["appLabel"] = "quizmo"
        }
    }

    signingConfigs {
        if (!releaseKeystore.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    ?: error("Missing ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    ?: error("Missing ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                    ?: error("Missing ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            // `flutter run` signs with the local debug key; a separate package
            // keeps it from blocking the installed release/beta APK.
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appLabel"] = "quizmo debug"
        }
        release {
            // Debug signing remains available for explicitly requested local builds only.
            signingConfig = signingConfigs.getByName(
                if (releaseKeystore.isNullOrBlank()) "debug" else "release"
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
