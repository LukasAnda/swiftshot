import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    // AGP 9: Android targets of KMP modules use the Android KMP library plugin (`kotlin { android {} }`).
    alias(libs.plugins.android.kotlin.multiplatform.library)
    alias(libs.plugins.compose.multiplatform)
    alias(libs.plugins.compose.compiler)
}

kotlin {
    jvmToolchain(21)

    android {
        namespace = "com.swiftshot.demo.shared"
        compileSdk = libs.versions.android.compileSdk.get().toInt()
        minSdk = libs.versions.android.minSdk.get().toInt()
        compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
        // Compose resources (strings) are packaged as Android assets.
        androidResources { enable = true }
    }

    listOf(iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    jvm("desktop") {
        compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
    }

    compilerOptions {
        optIn.addAll(
            "androidx.compose.material3.ExperimentalMaterial3Api",
            "androidx.compose.material3.ExperimentalMaterial3ExpressiveApi",
        )
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }

    sourceSets {
        commonMain.dependencies {
            api(libs.compose.runtime)
            api(libs.compose.ui)
            implementation(libs.compose.foundation)
            implementation(libs.compose.material3)
            implementation(libs.compose.material3.navigation.suite)
            implementation(libs.compose.components.resources)
            // The multiplatform AndroidX @Preview annotation (androidx.compose.ui.tooling.preview.Preview).
            implementation(libs.compose.ui.tooling.preview)
        }
        named("desktopMain").dependencies {
            implementation(libs.icu4j)
        }
    }
}

dependencies {
    // Preview rendering on Android (the KMP library plugin has no debug variant).
    "androidRuntimeClasspath"(libs.compose.ui.tooling)
}

compose.resources {
    packageOfResClass = "com.swiftshot.demo.resources"
    generateResClass = always
}
