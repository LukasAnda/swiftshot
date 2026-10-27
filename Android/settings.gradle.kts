rootProject.name = "swiftshot-android"

pluginManagement {
    repositories { gradlePluginPortal(); mavenCentral() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}

// cli: the orchestrator (JDK + Kotlin stdlib only, shipped as one jar).
// worker: runs inside the app's classpath and renders through layoutlib (Paparazzi's SDK).
include(":cli", ":worker")
