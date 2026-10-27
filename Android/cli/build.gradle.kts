plugins { kotlin("jvm") }

kotlin { jvmToolchain(21) }

dependencies {
    implementation("org.ow2.asm:asm:9.9")
    testImplementation(kotlin("test"))
}

tasks.test { useJUnitPlatform() }

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
