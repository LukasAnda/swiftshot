package swiftshot.android

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SnapshotModulesTest {
    private val dir: File = Files.createTempDirectory("swiftshot-snap").toFile()

    @AfterTest fun cleanUp() { dir.deleteRecursively() }

    private fun write(path: String, text: String) = File(dir, path).apply { parentFile.mkdirs(); writeText(text) }
    private fun find() = SnapshotModules.find(dir)
    private fun one(): SnapshotModule = find().also { assertEquals(1, it.size, it.toString()) }.single()

    private val paparazzi = "app.cash.paparazzi"
    private val roborazzi = "io.github.takahirom.roborazzi"
    private val roboPackage = "com.github.takahirom.roborazzi"

    @Test fun directPluginKotlinDsl() {
        write("settings.gradle.kts", """include(":app")""")
        write("app/build.gradle.kts", """plugins { id("$paparazzi") }""")
        val m = one()
        assertEquals(":app", m.path)
        assertEquals(File(dir, "app"), m.dir)
        assertEquals(setOf(SnapshotTool.PAPARAZZI), m.tools)
        assertEquals(listOf("plugin $paparazzi"), m.via)
    }

    @Test fun groovyApplyPlugin() {
        write("settings.gradle", "include ':a', ':b'")
        write("a/build.gradle", "apply plugin: '$paparazzi'")
        write("b/build.gradle", "plugins {\n  id '$roborazzi'\n}")
        val m = find()
        assertEquals(listOf(":a", ":b"), m.map { it.path })
        assertEquals(setOf(SnapshotTool.PAPARAZZI), m[0].tools)
        assertEquals(setOf(SnapshotTool.ROBORAZZI), m[1].tools)
        assertEquals(listOf("plugin $roborazzi"), m[1].via)
    }

    @Test fun commentedPluginIsIgnored() {
        write("settings.gradle.kts", """include(":app")""")
        write("app/build.gradle.kts", "plugins {\n // id(\"$paparazzi\")\n /* id(\"$roborazzi\") */\n}")
        assertTrue(find().isEmpty())
    }

    @Test fun dependencyCoordinateIsNotAPlugin() {
        write("settings.gradle.kts", """include(":app")""")
        write("app/build.gradle.kts", """dependencies { testImplementation("$paparazzi:paparazzi:1.3.5") }""")
        assertTrue(find().isEmpty())
    }

    @Test fun catalogAlias() {
        write("settings.gradle.kts", """include(":a", ":b")""")
        write("gradle/libs.versions.toml", """
            [plugins]
            paparazzi = { id = "$paparazzi", version = "1.3.5" }
            roborazzi-plugin = { id = "$roborazzi", version.ref = "r" }
        """.trimIndent())
        write("a/build.gradle.kts", "plugins { alias(libs.plugins.paparazzi) }")
        write("b/build.gradle.kts", "plugins { alias(libs.plugins.roborazzi.plugin) }")
        val m = find()
        assertEquals(listOf("alias libs.plugins.paparazzi"), m[0].via)
        assertEquals(setOf(SnapshotTool.PAPARAZZI), m[0].tools)
        assertEquals(listOf("alias libs.plugins.roborazzi.plugin"), m[1].via)
        assertEquals(setOf(SnapshotTool.ROBORAZZI), m[1].tools)
    }

    private fun conventionBuild(base: String, register: String = "nowinandroid.android.roborazzi", body: String) {
        write("$base/build.gradle.kts", """
            gradlePlugin { plugins { register("x") { id = "$register"; implementationClass = "com.x.ScreenshotConventionPlugin" } } }
        """.trimIndent())
        write("$base/src/main/kotlin/com/x/ScreenshotConventionPlugin.kt", """
            package com.x
            class ScreenshotConventionPlugin : Plugin<Project> {
                override fun apply(target: Project) { with(target) { $body } }
            }
        """.trimIndent())
    }

    @Test fun conventionPluginViaPluginManager() {
        write("settings.gradle.kts", "pluginManagement { includeBuild(\"build-logic\") }\ninclude(\":feature\", \":other\")")
        conventionBuild("build-logic/convention", body = """pluginManager.apply("$roborazzi")""")
        write("feature/build.gradle.kts", """plugins { id("nowinandroid.android.roborazzi") }""")
        write("other/build.gradle.kts", """plugins { id("com.android.library") }""")
        val m = one()
        assertEquals(":feature", m.path)
        assertEquals(setOf(SnapshotTool.ROBORAZZI), m.tools)
        assertEquals(listOf("convention plugin nowinandroid.android.roborazzi"), m.via)
    }

    @Test fun conventionPluginViaApplyPluginNamedArgument() {
        write("settings.gradle.kts", """include(":feature")""")
        conventionBuild("buildSrc", body = """apply(plugin = "$paparazzi")""")
        write("feature/build.gradle.kts", """plugins { id("nowinandroid.android.roborazzi") }""")
        assertEquals(setOf(SnapshotTool.PAPARAZZI), one().tools)
    }

    @Test fun conventionPluginViaCatalogAlias() {
        write("settings.gradle.kts", """include(":feature")""")
        write("gradle/libs.versions.toml", "[plugins]\nnowinandroid-android-roborazzi = { id = \"nowinandroid.android.roborazzi\" }\nroborazzi = { id = \"$roborazzi\" }\n")
        conventionBuild("build-logic/convention", body = """pluginManager.apply(libs.findPlugin("roborazzi").get().get().pluginId)""")
        write("feature/build.gradle.kts", "plugins { alias(libs.plugins.nowinandroid.android.roborazzi) }")
        val m = one()
        assertEquals(setOf(SnapshotTool.ROBORAZZI), m.tools)
        assertEquals(listOf("convention plugin nowinandroid.android.roborazzi"), m.via)
    }

    @Test fun precompiledScriptPlugin() {
        write("settings.gradle.kts", """include(":feature")""")
        write("buildSrc/src/main/kotlin/screenshots.gradle.kts", """plugins { id("$paparazzi") }""")
        write("feature/build.gradle.kts", """plugins { id("screenshots") }""")
        val m = one()
        assertEquals(setOf(SnapshotTool.PAPARAZZI), m.tools)
        assertEquals(listOf("convention plugin screenshots"), m.via)
    }

    @Test fun conventionPluginThatAppliesNothingIsIgnored() {
        write("settings.gradle.kts", """include(":feature")""")
        conventionBuild("build-logic/convention", body = """pluginManager.apply("com.android.library")""")
        write("feature/build.gradle.kts", """plugins { id("nowinandroid.android.roborazzi") }""")
        assertTrue(find().isEmpty())
    }

    @Test fun importsOnly() {
        write("settings.gradle.kts", """include(":ui")""")
        write("ui/build.gradle.kts", "plugins { id(\"com.android.library\") }")
        write("ui/src/test/kotlin/X.kt", "import app.cash.paparazzi.Paparazzi\nclass X")
        val m = one()
        assertEquals(setOf(SnapshotTool.PAPARAZZI), m.tools)
        assertEquals(listOf("imports"), m.via)
    }

    @Test fun pluginAndImportsMerge() {
        write("settings.gradle.kts", """include(":ui")""")
        write("ui/build.gradle.kts", "plugins { id(\"$roborazzi\") }")
        write("ui/src/test/kotlin/X.kt", "import app.cash.paparazzi.Paparazzi\nimport $roboPackage.captureRoboImage")
        val m = one()
        assertEquals(setOf(SnapshotTool.PAPARAZZI, SnapshotTool.ROBORAZZI), m.tools)
        assertEquals(listOf("plugin $roborazzi", "imports"), m.via)
    }

    @Test fun kmpSourceSets() {
        write("settings.gradle.kts", """include(":a", ":b", ":c", ":d", ":e")""")
        for ((m, set) in listOf("a" to "desktopTest", "b" to "iosTest", "c" to "androidUnitTest", "d" to "commonTest"))
            write("$m/src/$set/kotlin/T.kt", "import $roboPackage.*")
        write("e/src/main/kotlin/T.kt", "import $roboPackage.*")
        assertEquals(listOf(":a", ":b", ":c", ":d"), find().map { it.path })
    }

    @Test fun customProjectDir() {
        write("settings.gradle.kts", """
            include(":feature:checkout")
            project(":feature:checkout").projectDir = file("features/checkout")
        """.trimIndent())
        write("features/checkout/build.gradle.kts", """plugins { id("$paparazzi") }""")
        assertEquals(File(dir, "features/checkout"), SnapshotModules.projects(dir)[":feature:checkout"])
        assertEquals(File(dir, "features/checkout"), one().dir)
    }

    @Test fun projectDirFileConstructor() {
        write("settings.gradle", "include ':x'\nproject(':x').projectDir = new File(settingsDir, '../x2')")
        assertEquals(dir.parentFile.resolve("x2"), SnapshotModules.projects(dir)[":x"])
    }

    @Test fun includeBuildProjects() {
        write("settings.gradle.kts", """includeBuild("shared")""")
        write("shared/settings.gradle.kts", """include(":lib")""")
        write("shared/lib/build.gradle.kts", """plugins { id("$paparazzi") }""")
        assertEquals(File(dir, "shared/lib"), SnapshotModules.projects(dir)[":shared:lib"])
        assertEquals(listOf(":shared:lib"), find().map { it.path })
    }

    @Test fun noTools() {
        write("settings.gradle.kts", """include(":app")""")
        write("app/build.gradle.kts", """plugins { id("com.android.application") }""")
        write("app/src/test/kotlin/T.kt", "import org.junit.Test")
        assertTrue(find().isEmpty())
    }

    @Test fun legacyRoborazziImportPackageAlsoCounts() {
        write("settings.gradle.kts", """include(":a")""")
        write("a/src/test/kotlin/T.kt", "import $roborazzi.RoborazziRule")
        assertEquals(setOf(SnapshotTool.ROBORAZZI), one().tools)
    }

    @Test fun conventionIdFromCatalog() {
        write("settings.gradle.kts", """include(":feature")""")
        write("gradle/libs.versions.toml", "[plugins]\nshots = { id = \"my.shots\" }\n")
        write("build-logic/convention/build.gradle.kts", "gradlePlugin { plugins { register(\"x\") { id = libs.plugins.shots.get().pluginId; implementationClass = \"ShotsPlugin\" } } }")
        write("build-logic/convention/src/main/kotlin/ShotsPlugin.kt", "class ShotsPlugin { fun apply() { pluginManager.apply(\"$paparazzi\") } }")
        write("feature/build.gradle.kts", "plugins { id(\"my.shots\") }")
        assertEquals(listOf("convention plugin my.shots"), one().via)
    }

    @Test fun groovyStyleGradlePluginRegistration() {
        write("settings.gradle", "include ':feature'")
        write("buildSrc/build.gradle", "gradlePlugin {\n plugins {\n  shots {\n   id = 'my.shots'\n   implementationClass = 'p.ShotsPlugin'\n  }\n }\n}")
        write("buildSrc/src/main/groovy/p/ShotsPlugin.groovy", "class ShotsPlugin { void apply(p) { p.apply plugin: '$paparazzi' } }")
        write("feature/build.gradle", "plugins { id 'my.shots' }")
        assertEquals(listOf("convention plugin my.shots"), one().via)
    }

    @Test fun multiLineIncludeAndNoIncludeBuild() {
        assertEquals(listOf(":a", ":b", ":c", ":d"), Init.modules("include(\n  \":a\",\n  \":b\"\n)\ninclude ':c',\n  ':d'\nincludeBuild(\"shared\")\nincludeFlat(\"flat\")"))
    }

    @Test fun projectDirWithoutLiteralFallsBackToDefault() {
        write("settings.gradle.kts", "include(\":a\", \":b\")\nval n = \"x\"\nproject(\":a\").projectDir = File(rootDir, n)\nproject(\":b\").projectDir = file(n)")
        val p = SnapshotModules.projects(dir)
        assertEquals(File(dir, "a"), p[":a"])
        assertEquals(File(dir, "b"), p[":b"])
    }

    @Test fun projectDirRootDirInterpolation() {
        write("settings.gradle.kts", "include(\":a\", \":b\")\nproject(\":a\").projectDir = file(\"\$rootDir/mods/a\")\nproject(\":b\").projectDir = file(\"\${rootDir}/mods/b\")")
        val p = SnapshotModules.projects(dir)
        assertEquals(File(dir, "mods/a"), p[":a"])
        assertEquals(File(dir, "mods/b"), p[":b"])
    }

    @Test fun projectDirFindProjectAndApplyForms() {
        write("settings.gradle.kts", "include(\":a\", \":b\")\nfindProject(\":a\")!!.projectDir = file(\"mods/a\")\nproject(\":b\").apply { projectDir = file(\"mods/b\") }")
        val p = SnapshotModules.projects(dir)
        assertEquals(File(dir, "mods/a"), p[":a"])
        assertEquals(File(dir, "mods/b"), p[":b"])
    }
}
