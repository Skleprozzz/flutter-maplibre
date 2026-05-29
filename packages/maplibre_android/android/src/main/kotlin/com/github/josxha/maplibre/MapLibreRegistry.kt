package com.github.josxha.maplibre

import android.annotation.SuppressLint
import android.widget.FrameLayout
import androidx.annotation.Keep

@Keep
@SuppressLint("StaticFieldLeak")
object MapLibreRegistry {
    public var flutterApi: FlutterApi? = null

    private val platformViews = mutableMapOf<Int, FrameLayout>()

    @JvmStatic
    fun registerPlatformView(
        viewId: Int,
        view: FrameLayout,
    ) {
        platformViews[viewId] = view
    }

    @JvmStatic
    fun unregisterPlatformView(viewId: Int) {
        platformViews.remove(viewId)
    }

    @JvmStatic
    fun getPlatformView(viewId: Int): FrameLayout? = platformViews[viewId]
}
