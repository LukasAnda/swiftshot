package com.swiftshot.demo.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.text.intl.Locale
import platform.Foundation.NSDate
import platform.Foundation.NSDateFormatter
import platform.Foundation.NSLocale
import platform.Foundation.NSNumber
import platform.Foundation.NSNumberFormatter
import platform.Foundation.NSNumberFormatterDecimalStyle
import platform.Foundation.NSNumberFormatterPercentStyle
import platform.Foundation.NSTimeZone
import platform.Foundation.dateWithTimeIntervalSince1970
import platform.Foundation.timeZoneWithAbbreviation

internal actual object PlatformFormat {
    actual fun date(epochSeconds: Long, skeleton: String, localeTag: String): String {
        val locale = NSLocale(localeIdentifier = localeTag)
        val formatter = NSDateFormatter()
        formatter.locale = locale
        formatter.timeZone = NSTimeZone.timeZoneWithAbbreviation("UTC")!!
        formatter.dateFormat = NSDateFormatter.dateFormatFromTemplate(skeleton, 0u, locale) ?: skeleton
        return formatter.stringFromDate(NSDate.dateWithTimeIntervalSince1970(epochSeconds.toDouble()))
    }

    actual fun percent(value: Double, localeTag: String): String =
        numberFormatter(localeTag, NSNumberFormatterPercentStyle).stringFromNumber(NSNumber(double = value)) ?: ""

    actual fun number(value: Int, localeTag: String): String =
        numberFormatter(localeTag, NSNumberFormatterDecimalStyle).stringFromNumber(NSNumber(int = value)) ?: ""

    private fun numberFormatter(localeTag: String, style: ULong) = NSNumberFormatter().apply {
        locale = NSLocale(localeIdentifier = localeTag)
        numberStyle = style
        maximumFractionDigits = 0u
    }
}

@Composable
@ReadOnlyComposable
actual fun currentLocaleTag(): String = Locale.current.toLanguageTag()
