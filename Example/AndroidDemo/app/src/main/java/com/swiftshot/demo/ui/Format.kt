package com.swiftshot.demo.ui

import android.icu.text.DateFormat
import android.icu.text.NumberFormat
import android.icu.util.TimeZone
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import java.util.Date
import java.util.Locale

/**
 * Locale-aware formatting pinned to UTC, so the fixed dates read the same on every device and
 * in every time zone a renderer might use. Skeletons let ICU pick each locale's own order.
 */
object Format {
    const val WEEKDAY_DAY_MONTH = "EEEEMMMMd"
    const val WEEKDAY_DAY_MONTH_YEAR = "EEEEMMMMdy"
    const val MONTH_YEAR = "MMMMy"
    const val DAY = "d"
    const val WEEKDAY_SHORT = "EEE"
    const val WEEKDAY_NARROW = "EEEEE"
    const val TIME = "jmm"

    fun date(epochSeconds: Long, skeleton: String, locale: Locale): String =
        DateFormat.getInstanceForSkeleton(skeleton, locale).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(epochSeconds * 1_000))

    fun percent(value: Double, locale: Locale): String = NumberFormat.getPercentInstance(locale).format(value)

    fun number(value: Int, locale: Locale): String = NumberFormat.getIntegerInstance(locale).format(value.toLong())
}

@Composable
@ReadOnlyComposable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

@Composable
@ReadOnlyComposable
fun formatDate(epochSeconds: Long, skeleton: String): String = Format.date(epochSeconds, skeleton, currentLocale())

@Composable
@ReadOnlyComposable
fun formatPercent(value: Double): String = Format.percent(value, currentLocale())

@Composable
@ReadOnlyComposable
fun formatNumber(value: Int): String = Format.number(value, currentLocale())
