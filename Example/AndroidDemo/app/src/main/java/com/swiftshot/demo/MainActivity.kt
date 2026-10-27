package com.swiftshot.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import com.swiftshot.demo.ui.HabitsApp
import com.swiftshot.demo.ui.theme.HabitsTheme
import com.swiftshot.demo.ui.welcome.WelcomeScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            HabitsTheme {
                var started by rememberSaveable { mutableStateOf(false) }
                if (started) {
                    HabitsApp()
                } else {
                    WelcomeScreen(onGetStarted = { started = true }, onSignIn = { started = true })
                }
            }
        }
    }
}
