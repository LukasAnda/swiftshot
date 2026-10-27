package com.swiftshot.demo.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.text.intl.Locale
import com.ibm.icu.text.DateFormat
import com.ibm.icu.text.NumberFormat
import com.ibm.icu.util.TimeZone
import com.ibm.icu.util.ULocale
import java.util.Date

// ICU4J: the same skeleton matching and CLDR data as android.icu, so desktop reads like Android.
internal actual object PlatformFormat {
    actual fun date(epochSeconds: Long, skeleton: String, localeTag: String): String =
        DateFormat.getInstanceForSkeleton(skeleton, ULocale.forLanguageTag(localeTag)).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(epochSeconds * 1_000))

    actual fun percent(value: Double, localeTag: String): String =
        NumberFormat.getPercentInstance(ULocale.forLanguageTag(localeTag)).format(value)

    actual fun number(value: Int, localeTag: String): String =
        NumberFormat.getIntegerInstance(ULocale.forLanguageTag(localeTag)).format(value.toLong())
}

@Composable
@ReadOnlyComposable
actual fun currentLocaleTag(): String = Locale.current.toLanguageTag()
