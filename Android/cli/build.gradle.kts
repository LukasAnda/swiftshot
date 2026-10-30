plugins { kotlin("jvm") }

kotlin { jvmToolchain(21) }

dependencies {
    implementation("org.ow2.asm:asm:9.9")
    // Android Studio's device art is WebP; the JDK reads only PNG and JPEG.
    implementation("com.twelvemonkeys.imageio:imageio-webp:3.12.0")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    // Fixtures shared with the Swift implementation (Shared/testdata).
    val testdata = rootProject.file("../Shared/testdata")
    inputs.dir(testdata)
    systemProperty("swiftshot.testdata", testdata.absolutePath)
}

// One self-contained jar: `java -jar swiftshot-android.jar`.
tasks.jar {
    archiveFileName.set("swiftshot-android.jar")
    manifest { attributes["Main-Class"] = "swiftshot.android.MainKt" }
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) }) {
        exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA", "META-INF/versions/**", "module-info.class")
    }
}

sourceSets.main { kotlin.srcDir("../shared") }

// The release version (make dist VERSION=…), read back by `swiftshot --version`.
tasks.jar { manifest { attributes["Implementation-Version"] = (findProperty("swiftshot.version") ?: "dev").toString() } }
