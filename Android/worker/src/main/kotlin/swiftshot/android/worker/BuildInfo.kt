package swiftshot.android.worker

import java.lang.reflect.Modifier

/**
 * Device identity in android.os.Build. Layoutlib leaves MODEL, MANUFACTURER and friends null, and
 * libraries that read them (Wear Compose checks `Build.MODEL` for Galaxy watches) crash in
 * composition. Null fields get stable values for the device being rendered.
 */
object BuildInfo {
    fun fill(model: String, watch: Boolean) {
        val build = runCatching { Class.forName("android.os.Build") }.getOrNull() ?: return
        val values = mapOf(
            "MANUFACTURER" to "Google", "BRAND" to "google", "MODEL" to model,
            "DEVICE" to if (watch) "wear" else "generic", "PRODUCT" to if (watch) "wear" else "sdk_gphone",
            "HARDWARE" to "ranchu", "BOARD" to "goldfish", "BOOTLOADER" to "unknown", "TYPE" to "user",
            "TAGS" to "release-keys", "FINGERPRINT" to "google/sdk/generic:release-keys", "DISPLAY" to "swiftshot",
            "HOST" to "swiftshot", "ID" to "swiftshot", "USER" to "swiftshot",
        )
        for ((name, value) in values) {
            val field = runCatching { build.getDeclaredField(name) }.getOrNull() ?: continue
            if (!Modifier.isStatic(field.modifiers) || field.type != String::class.java) continue
            field.isAccessible = true
            if (name != "MODEL" && field.get(null) != null) continue
            unsafe.putObject(unsafe.staticFieldBase(field), unsafe.staticFieldOffset(field), value)
        }
    }

    @Suppress("DEPRECATION")
    private val unsafe: sun.misc.Unsafe by lazy {
        sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as sun.misc.Unsafe
    }
}
