plugins {
    kotlin("jvm")
    kotlin("plugin.compose")
}

kotlin { jvmToolchain(21) }

// Compose comes from the app's own desktop classpath at run time.
dependencies {
    compileOnly("org.jetbrains.compose.ui:ui-desktop:1.12.2")
    compileOnly("org.jetbrains.compose.runtime:runtime-desktop:1.12.2")
}

sourceSets.main { kotlin.srcDir("../shared") }

tasks.jar { archiveFileName.set("swiftshot-desktop-worker.jar") }
