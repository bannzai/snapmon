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
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    id("com.google.firebase.crashlytics") version("3.0.7") apply false
    // END: FlutterFire Configuration
    // 2.3.21: firebase-auth 25.0.0 等の Kotlin メタデータが 2.4.0 で、Kotlin のコンパイラは 1 つ先の版のメタデータまでしか読めないため (2.2.20 では読めずビルドが失敗した)
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

include(":app")
