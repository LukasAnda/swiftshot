package swiftshot.android

import java.io.File

/** The machine this runs on: iOS rendering needs a Mac with Xcode, everything else runs anywhere. */
object Host {
    val mac: Boolean = System.getProperty("os.name").orEmpty().startsWith("Mac")
}

/** Why an iOS project, or an iOS-only request, can't be rendered here. */
fun iosOnly(dir: File?): String {
    val project = dir?.listFiles()?.firstOrNull { it.name.endsWith(".xcworkspace") || it.name.endsWith(".xcodeproj") }
    val what = project?.let { "${it.name} is an iOS project" } ?: "iOS rendering"
    return if (Host.mac) "$what: iOS is rendered by the Mac tool (brew install lukasanda/tap/swiftshot), not this Android renderer."
    else "$what: iOS needs a Mac with Xcode. Here, swiftshot renders Android, desktop and the Android and desktop targets of Compose Multiplatform."
}
