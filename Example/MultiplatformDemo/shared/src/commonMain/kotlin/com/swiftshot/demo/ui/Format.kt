package com.swiftshot.demo.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable

/**
 * Locale-aware formatting pinned to UTC, so the fixed dates read the same on every device and
 * in every time zone a renderer might use. Skeletons let each platform's ICU/CLDR data pick the
 * locale's own order; they are written in canonical field order (year, month, weekday, day, hour,
 * minute) so every platform accepts them.
 */
object Format {
    const val WEEKDAY_DAY_MONTH = "MMMMEEEEd"
    const val WEEKDAY_DAY_MONTH_YEAR = "yMMMMEEEEd"
    const val MONTH_YEAR = "yMMMM"
    const val DAY = "d"
    const val WEEKDAY_SHORT = "EEE"
    const val WEEKDAY_NARROW = "EEEEE"
    const val TIME = "jmm"

    fun date(epochSeconds: Long, skeleton: String, localeTag: String): String =
        PlatformFormat.date(epochSeconds, skeleton, localeTag)

    fun percent(value: Double, localeTag: String): String = PlatformFormat.percent(value, localeTag)

    fun number(value: Int, localeTag: String): String = PlatformFormat.number(value, localeTag)
}

/** The platform's date and number formatters (android.icu, Foundation, ICU4J). */
internal expect object PlatformFormat {
    fun date(epochSeconds: Long, skeleton: String, localeTag: String): String
    fun percent(value: Double, localeTag: String): String
    fun number(value: Int, localeTag: String): String
}

/** The BCP 47 tag of the locale the UI is composed in (follows preview `locale` on Android). */
@Composable
@ReadOnlyComposable
expect fun currentLocaleTag(): String

@Composable
@ReadOnlyComposable
fun formatDate(epochSeconds: Long, skeleton: String): String = Format.date(epochSeconds, skeleton, currentLocaleTag())

@Composable
@ReadOnlyComposable
fun formatPercent(value: Double): String = Format.percent(value, currentLocaleTag())

@Composable
@ReadOnlyComposable
fun formatNumber(value: Int): String = Format.number(value, currentLocaleTag())
