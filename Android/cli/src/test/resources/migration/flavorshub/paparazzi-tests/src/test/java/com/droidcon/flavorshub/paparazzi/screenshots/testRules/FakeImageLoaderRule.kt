package com.droidcon.flavorshub.paparazzi.screenshots.testRules

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import coil3.ColorImage
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.annotation.DelicateCoilApi
import coil3.annotation.ExperimentalCoilApi
import coil3.test.FakeImageLoaderEngine
import org.junit.rules.TestWatcher
import org.junit.runner.Description

class FakeImageLoaderRule(val context: () -> Context) : TestWatcher() {
    @OptIn(ExperimentalCoilApi::class, DelicateCoilApi::class)
    override fun starting(description: Description?) {
        super.starting(description)
        val engine = FakeImageLoaderEngine.Builder()
            .intercept({ request -> true }, ColorImage(Color.Red.toArgb()))
            .build()
        val imageLoader = ImageLoader.Builder(context())
            .components { add(engine) }
            .build()
        SingletonImageLoader.setUnsafe(imageLoader)
    }
}