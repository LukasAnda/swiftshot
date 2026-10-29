package com.droidcon.flavorshub.roborazzi.screenshots.testrules

import android.app.Activity
import android.app.Application
import android.content.ComponentName
import androidx.test.core.app.ApplicationProvider
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.robolectric.Shadows

class AddActivityToRobolectricRule(val clazz: Class<out Activity>): TestWatcher() {
    override fun starting(description: Description?) {
        super.starting(description)
        val appContext: Application = ApplicationProvider.getApplicationContext()
        Shadows
            .shadowOf(appContext.packageManager)
            .addActivityIfNotPresent(ComponentName(appContext, clazz))
    }
}