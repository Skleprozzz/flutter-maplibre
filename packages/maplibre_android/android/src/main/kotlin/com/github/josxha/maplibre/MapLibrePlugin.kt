package com.github.josxha.maplibre

// if imports can't resolve:
// - remove all .idea/ folders
// - open example/android/build.gradle.kts as project
// - sync project to download dependencies

import android.app.Activity
import android.content.Context
import android.view.View
import android.widget.FrameLayout
import com.github.josxha.maplibre.location.LocationModelManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.maplibre.android.location.permissions.PermissionsManager

/** MapLibrePlugin */
class MapLibrePlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private var permissionsManager: PermissionsManager? = null
    private var locationModelChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory(
                "plugins.flutter.io/maplibre",
                MapLibreMapFactory(),
            )

        locationModelChannel =
            MethodChannel(binding.binaryMessenger, "maplibre/location_model").also {
                channel ->
                channel.setMethodCallHandler(::onLocationModelMethodCall)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        locationModelChannel?.setMethodCallHandler(null)
        locationModelChannel = null
    }

    private fun onLocationModelMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "attach" -> {
                    val viewId = call.argument<Int>("viewId")!!
                    val files = parseLocationModelFiles(call.argument("files"))
                    val fileName = call.argument<String>("fileName")!!
                    val scale = call.argument<Double>("scale")!!.toFloat()
                    LocationModelManager.attach(viewId, files, fileName, scale)
                    result.success(null)
                }
                "update" -> {
                    val viewId = call.argument<Int>("viewId")!!
                    val screenX = call.argument<Double>("screenX")!!.toFloat()
                    val screenY = call.argument<Double>("screenY")!!.toFloat()
                    val bearing = call.argument<Double>("bearing")!!.toFloat()
                    val visible = call.argument<Boolean>("visible")!!
                    LocationModelManager.update(viewId, screenX, screenY, bearing, visible)
                    result.success(null)
                }
                "detach" -> {
                    val viewId = call.argument<Int>("viewId")!!
                    LocationModelManager.detach(viewId)
                    result.success(null)
                }
                "unregisterPlatformView" -> {
                    val viewId = call.argument<Int>("viewId")!!
                    MapLibreRegistry.unregisterPlatformView(viewId)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("location_model_error", e.message, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        permissionsManager?.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
        return true
    }
}

class MapLibreMapFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?,
    ): PlatformView {
        val delegate = MapLibreRegistry.flutterApi!!.createPlatformView(viewId)
        return RegisteredPlatformView(viewId, delegate).also {
            // Ensure the native registry is populated before Dart attaches overlays.
            it.getView()
        }
    }
}

private class RegisteredPlatformView(
    private val viewId: Int,
    private val delegate: PlatformView,
) : PlatformView {
    override fun getView(): View {
        val view =
            checkNotNull(delegate.getView()) {
                "MapLibre platform view is not available"
            }
        if (view is FrameLayout) {
            MapLibreRegistry.registerPlatformView(viewId, view)
        }
        return view
    }

    override fun dispose() {
        MapLibreRegistry.unregisterPlatformView(viewId)
        LocationModelManager.detach(viewId)
        delegate.dispose()
    }

    override fun onFlutterViewAttached(flutterView: View) {
        delegate.onFlutterViewAttached(flutterView)
    }

    override fun onFlutterViewDetached() {
        delegate.onFlutterViewDetached()
    }

    override fun onInputConnectionLocked() {
        delegate.onInputConnectionLocked()
    }

    override fun onInputConnectionUnlocked() {
        delegate.onInputConnectionUnlocked()
    }
}

private fun parseLocationModelFiles(raw: Any?): Map<String, ByteArray> {
    val map = raw as? Map<*, *> ?: return emptyMap()
    return buildMap {
        for ((key, value) in map) {
            val name = key as? String ?: continue
            val bytes =
                when (value) {
                    is ByteArray -> value
                    is List<*> ->
                        value.map { (it as Number).toByte() }.toByteArray()
                    else -> continue
                }
            put(name, bytes)
        }
    }
}
