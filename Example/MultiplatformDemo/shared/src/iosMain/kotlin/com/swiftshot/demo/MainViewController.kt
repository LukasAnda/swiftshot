package com.swiftshot.demo

import androidx.compose.ui.window.ComposeUIViewController
import platform.UIKit.UIViewController

/** The iOS entry point: the shared app in a UIViewController (Swift: `MainViewControllerKt.MainViewController()`). */
fun MainViewController(): UIViewController = ComposeUIViewController { App() }
