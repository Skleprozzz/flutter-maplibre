package com.github.josxha.maplibre.location

import android.graphics.Color
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import androidx.annotation.Keep
import io.github.sceneview.SceneView
import io.github.sceneview.math.Rotation
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

@Keep
object LocationModelManager {
    private val controllers = mutableMapOf<Int, LocationModelController>()

    @JvmStatic
    fun attach(
        viewId: Int,
        files: Map<String, ByteArray>,
        fileName: String,
        scale: Float,
    ) {
        val parent = com.github.josxha.maplibre.MapLibreRegistry.getPlatformView(viewId)
            ?: return
        detach(viewId)
        controllers[viewId] =
            LocationModelController(parent, files, fileName, scale)
    }

    @JvmStatic
    fun update(
        viewId: Int,
        screenX: Float,
        screenY: Float,
        bearing: Float,
        visible: Boolean,
    ) {
        controllers[viewId]?.update(screenX, screenY, bearing, visible)
    }

    @JvmStatic
    fun detach(viewId: Int) {
        controllers.remove(viewId)?.dispose()
    }
}

@Keep
private class LocationModelController(
    private val parent: FrameLayout,
    files: Map<String, ByteArray>,
    fileName: String,
    private val scale: Float,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val container =
        FrameLayout(parent.context).apply {
            isClickable = false
            isFocusable = false
        }
    private val sceneView = SceneView(parent.context)
    private var modelNode: ModelNode? = null
    private val modelSizePx = dpToPx(parent, MODEL_SIZE_DP)

    init {
        container.addView(
            sceneView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        parent.addView(
            container,
            FrameLayout.LayoutParams(modelSizePx, modelSizePx).apply {
                gravity = Gravity.TOP or Gravity.START
            },
        )
        sceneView.setBackgroundColor(Color.TRANSPARENT)
        sceneView.isClickable = false
        sceneView.isFocusable = false

        val modelFile =
            writeModelCache(parent.context.cacheDir, files, fileName)
                ?: run {
                    container.visibility = android.view.View.GONE
                    return
                }

        scope.launch {
            try {
                val instance = sceneView.modelLoader.createModelInstance(modelFile)
                val node =
                    ModelNode(
                        modelInstance = instance,
                        scaleToUnits = scale.coerceAtLeast(0.01f),
                    )
                modelNode = node
                sceneView.addChildNode(node)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load location model: ${modelFile.name}", e)
                container.visibility = android.view.View.GONE
            }
        }
    }

    fun update(
        screenX: Float,
        screenY: Float,
        bearing: Float,
        visible: Boolean,
    ) {
        container.visibility = if (visible) android.view.View.VISIBLE else android.view.View.GONE
        if (!visible) return

        val half = modelSizePx / 2f
        container.x = screenX - half
        container.y = screenY - modelSizePx
        modelNode?.rotation = Rotation(y = bearing)
    }

    fun dispose() {
        scope.cancel()
        parent.removeView(container)
    }

    private fun dpToPx(
        parent: FrameLayout,
        dp: Float,
    ): Int =
        TypedValue
            .applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                dp,
                parent.resources.displayMetrics,
            ).toInt()

    companion object {
        private const val TAG = "LocationModelManager"
        private const val MODEL_SIZE_DP = 96f

        private fun writeModelCache(
            cacheDir: File,
            files: Map<String, ByteArray>,
            fileName: String,
        ): File? {
            if (files.isEmpty()) return null
            val dir = File(cacheDir, "maplibre_location_models")
            dir.mkdirs()
            for ((name, bytes) in files) {
                File(dir, name).writeBytes(bytes)
            }
            return File(dir, fileName).takeIf { it.exists() }
        }
    }
}
