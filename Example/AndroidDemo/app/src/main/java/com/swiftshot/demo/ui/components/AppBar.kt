package com.swiftshot.demo.ui.components

import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MediumFlexibleTopAppBar
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.style.TextOverflow

/** The screens' shared top bar: a flexible medium bar with an optional subtitle, on the canvas. */
@Composable
fun HabitsTopBar(
    title: String,
    scrollBehavior: TopAppBarScrollBehavior,
    subtitle: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = MaterialTheme.colorScheme
    MediumFlexibleTopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        subtitle = subtitle?.let { { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis) } },
        actions = actions,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = colors.background,
            scrolledContainerColor = colors.surfaceContainer,
            subtitleContentColor = colors.onSurfaceVariant,
        ),
        scrollBehavior = scrollBehavior,
    )
}
