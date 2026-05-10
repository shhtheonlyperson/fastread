plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.shhtheonlyperson.fastread.spike"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.shhtheonlyperson.fastread.spike"
        // Pixel 8 launched with Android 14 (API 34) — that's our floor
        // because we depend on the latest ICU rev for Trad-Chinese
        // word segmentation and the current Compose Material 3 render
        // path. Anything older means a different ICU dictionary and a
        // separate parity story we don't want to own for a spike.
        minSdk = 34
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.runtime:runtime")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    // Real org.json on the JVM unit-test classpath; the Android stub
    // library on the unit-test path throws "Method not mocked" otherwise.
    testImplementation("org.json:json:20240303")
}
