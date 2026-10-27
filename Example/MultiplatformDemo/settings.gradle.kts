pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "HabitsMultiplatformDemo"

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

include(":shared", ":androidApp", ":desktopApp")
