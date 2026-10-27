package com.swiftshot.demo

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.swiftshot.demo.ui.HabitsApp
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.welcome.WelcomeScreen

/** The whole app, shared by Android, iOS and desktop: Welcome first, then the four tabs. */
@Composable
fun App() {
    HabitsTheme {
        var started by rememberSaveable { mutableStateOf(false) }
        if (started) {
            HabitsApp()
        } else {
            WelcomeScreen(onGetStarted = { started = true }, onSignIn = { started = true })
        }
    }
}
