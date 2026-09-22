group = "dev.manishpanday.wear_os_tiles"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    // Built-in Kotlin compilation, which replaces this plugin application,
    // needs AGP 9 plus Flutter 3.47; the supported range starts at Flutter
    // 3.35, whose Gradle tooling does not apply KGP to plugin modules, so it
    // is applied here. Drop this line when that baseline moves up. See
    // https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
    id("kotlin-android")
}

android {
    namespace = "dev.manishpanday.wear_os_tiles"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = false
            all {
                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// Modern replacement for the deprecated `android.kotlinOptions {}` block,
// as required by the built-in Kotlin migration.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // Wear OS Tiles + ProtoLayout (current stable). `api` because apps
    // subclass WearTileService / WearComplicationService for extra ids.
    api("androidx.wear.tiles:tiles:1.6.2")
    api("androidx.wear.protolayout:protolayout:1.4.2")
    implementation("androidx.wear.protolayout:protolayout-expression:1.4.2")
    implementation("androidx.wear.protolayout:protolayout-material:1.4.2")
    // Watch-face complication data sources (current stable).
    api("androidx.wear.watchface:watchface-complications-data-source:1.3.0")
    implementation("androidx.concurrent:concurrent-futures:1.3.0")
    implementation("com.google.guava:listenablefuture:1.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("androidx.test:core:1.7.0")
}
