package com.swiftshot.demo.desktop

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.swiftshot.demo.App

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "Habits",
        state = rememberWindowState(width = 1100.dp, height = 760.dp),
    ) {
        App()
    }
}
