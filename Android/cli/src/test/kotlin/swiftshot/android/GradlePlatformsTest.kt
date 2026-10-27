package swiftshot.android

import kotlin.test.Test
import kotlin.test.assertEquals

class GradlePlatformsTest {
    @Test fun allPlatformsByDefault() = assertEquals(emptyList(), Gradle.gradlePlatforms(emptyList()))

    @Test fun iosAlsoPreparesDesktopNotAndroid() = assertEquals(listOf("ios", "desktop"), Gradle.gradlePlatforms(listOf("ios")))

    @Test fun noDuplicates() = assertEquals(listOf("desktop", "ios"), Gradle.gradlePlatforms(listOf("desktop", "ios")))

    @Test fun androidOnly() = assertEquals(listOf("android"), Gradle.gradlePlatforms(listOf("android")))
}
