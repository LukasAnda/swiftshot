plugins { kotlin("jvm") }

kotlin { jvmToolchain(21) }

// Everything here is provided at run time by the app's own classpath, which the init script
// resolves together with Paparazzi in the user's build.
dependencies {
    compileOnly("app.cash.paparazzi:paparazzi:2.0.0-alpha05.1")
    compileOnly("net.bytebuddy:byte-buddy:1.18.14")
    compileOnly("net.bytebuddy:byte-buddy-agent:1.18.14")
}

tasks.jar { archiveFileName.set("swiftshot-android-worker.jar") }

sourceSets.main { kotlin.srcDir("../shared") }
