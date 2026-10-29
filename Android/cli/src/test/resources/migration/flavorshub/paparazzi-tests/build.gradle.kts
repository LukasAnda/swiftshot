plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.paparazzi)
}

android {
    namespace = "com.droidcon.flavorshub.paparazzi"
    compileSdk = 35

    buildFeatures {
        compose = true
    }

    defaultConfig {
        minSdk = 28
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    implementation(project(":ui"))

    // Coil (image download)
    testImplementation(libs.coil.compose)
    testImplementation(libs.coil.network)
    testImplementation(libs.coil.test)

    // Immutable collections (stable classes to avoid recompositions)
    testImplementation(libs.kotlinx.collections.immutable.jvm)

    // Junit
    testImplementation(libs.junit)
    testImplementation(libs.test.parameter.injector)

    // Auto generate screenshots from previews
    testImplementation(libs.composable.preview.scanner)
}