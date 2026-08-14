import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { stream -> load(stream) }
    }
}

val dartDefines = (project.findProperty("dart-defines") as? String)
    ?.split(",")
    ?.filter { it.isNotBlank() }
    ?.mapNotNull { encodedDefine: String ->
        runCatching {
            String(Base64.getDecoder().decode(encodedDefine))
        }.getOrNull()
    }
    ?.mapNotNull { define: String ->
        val separatorIndex = define.indexOf('=')
        if (separatorIndex == -1) {
            null
        } else {
            define.substring(0, separatorIndex) to define.substring(separatorIndex + 1)
        }
    }
    ?.toMap()
    .orEmpty()

val googleMapsApiKey = dartDefines["GOOGLE_MAPS_API_KEY"]
    ?: dartDefines["MAPS_API_KEY"]
    ?: localProperties.getProperty("GOOGLE_MAPS_API_KEY")
    ?: localProperties.getProperty("MAPS_API_KEY")
    ?: ""
android {
    namespace = "com.citiride.citiride"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.citiride.citiride"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
