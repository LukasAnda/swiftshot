@file:OptIn(ExperimentalRoborazziApi::class)

import com.github.takahirom.roborazzi.ExperimentalRoborazziApi

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.roborazzi)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.kotlin.ksp)
}

android {
    namespace = "com.droidcon.flavorshub.roborazzi"
    compileSdk = 35

    defaultConfig {
        minSdk = 28
    }

    testOptions.unitTests {
        isIncludeAndroidResources = true
        all {
            it.systemProperties["robolectric.pixelCopyRenderMode"] = "hardware"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

roborazzi {
    generateComposePreviewRobolectricTests {
        enable = false
        packages = listOf("com.droidcon.flavorshub")
    }
}

dependencies {
    testImplementation(project(":app"))
    testImplementation(project(":ui"))
    testImplementation(project(":repositories"))

    // Dependency Injection
    testImplementation(libs.hilt.android.testing)
    kspTest(libs.dagger.hilt.compiler)

    // Coil (image download)
    testImplementation(libs.coil.compose)
    testImplementation(libs.coil.network)
    testImplementation(libs.coil.test)

    // Immutable collections (stable classes to avoid recompositions)
    testImplementation(libs.kotlinx.collections.immutable.jvm)

    // Junit
    testImplementation(libs.junit)
    testImplementation(libs.test.parameter.injector)

    // Compose Test Rules
    testImplementation(libs.androidx.junit)
    testImplementation(libs.androidx.compose.ui.test.junit4)

    // Roborazzi
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi.junit.rule)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi)
    testImplementation(libs.androidx.compose.ui.test.manifest) {
        because("Accessibility test requires it")
    }

    // Auto generate screenshots from previews
    testImplementation(libs.roborazzi.compose.preview.scanner.support)
    testImplementation(libs.composable.preview.scanner)
}