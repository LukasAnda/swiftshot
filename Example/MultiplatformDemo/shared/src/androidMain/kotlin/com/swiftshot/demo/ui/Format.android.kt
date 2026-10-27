package com.swiftshot.demo.ui

import android.icu.text.DateFormat
import android.icu.text.NumberFormat
import android.icu.util.TimeZone
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import java.util.Date
import java.util.Locale

internal actual object PlatformFormat {
    actual fun date(epochSeconds: Long, skeleton: String, localeTag: String): String =
        DateFormat.getInstanceForSkeleton(skeleton, Locale.forLanguageTag(localeTag)).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(epochSeconds * 1_000))

    actual fun percent(value: Double, localeTag: String): String =
        NumberFormat.getPercentInstance(Locale.forLanguageTag(localeTag)).format(value)

    actual fun number(value: Int, localeTag: String): String =
        NumberFormat.getIntegerInstance(Locale.forLanguageTag(localeTag)).format(value.toLong())
}

@Composable
@ReadOnlyComposable
actual fun currentLocaleTag(): String = LocalConfiguration.current.locales[0].toLanguageTag()
