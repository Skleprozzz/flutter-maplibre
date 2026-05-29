package com.github.josxha.maplibre.location

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.graphics.PixelFormat
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import androidx.annotation.Keep
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.filament.View as FilamentView
import io.github.sceneview.SceneView
import io.github.sceneview.math.Rotation
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

private const val TAG = "LocationModelManager"

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
        if (parent == null) {
            Log.w(TAG, "Platform view $viewId not ready for location model attach")
            return
        }
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
            setBackgroundColor(Color.TRANSPARENT)
            visibility = android.view.View.GONE
        }
    private val sceneView = SceneView(parent.context)
    private var modelNode: ModelNode? = null
    private val modelSizePx = dpToPx(parent, MODEL_SIZE_DP)
    private var pendingUpdate =
        PendingUpdate(screenX = 0f, screenY = 0f, bearing = 0f, visible = false)

    init {
        findLifecycle(parent.context)?.let { sceneView.lifecycle = it }
        configureTransparentSceneView(sceneView)

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

        val modelFile = writeModelCache(parent.context.cacheDir, files, fileName)
        if (modelFile == null) {
            Log.w(TAG, "No model files to load")
            container.visibility = android.view.View.GONE
        } else {
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
                    applyPendingUpdate()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to load location model: ${modelFile.name}", e)
                    container.visibility = android.view.View.GONE
                }
            }
        }
    }

    fun update(
        screenX: Float,
        screenY: Float,
        bearing: Float,
        visible: Boolean,
    ) {
        pendingUpdate =
            PendingUpdate(
                screenX = screenX,
                screenY = screenY,
                bearing = bearing,
                visible = visible,
            )
        applyPendingUpdate()
    }

    fun dispose() {
        scope.cancel()
        parent.removeView(container)
    }

    private fun applyPendingUpdate() {
        val node = modelNode ?: return
        val update = pendingUpdate
        container.visibility =
            if (update.visible) android.view.View.VISIBLE else android.view.View.GONE
        if (!update.visible) return

        val half = modelSizePx / 2f
        container.x = update.screenX - half
        container.y = update.screenY - half
        node.rotation = Rotation(y = update.bearing)
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

    private data class PendingUpdate(
        val screenX: Float,
        val screenY: Float,
        val bearing: Float,
        val visible: Boolean,
    )

    companion object {
        private const val MODEL_SIZE_DP = 96f

        private fun findLifecycle(context: Context): Lifecycle? {
            var current = context
            while (current is ContextWrapper) {
                if (current is LifecycleOwner) {
                    return current.lifecycle
                }
                current = current.baseContext
            }
            return null
        }

        private fun configureTransparentSceneView(sceneView: SceneView) {
            sceneView.setZOrderOnTop(true)
            sceneView.setBackgroundColor(Color.TRANSPARENT)
            sceneView.holder.setFormat(PixelFormat.TRANSLUCENT)
            sceneView.uiHelper.isOpaque = false
            sceneView.view.blendMode = FilamentView.BlendMode.TRANSLUCENT
            sceneView.renderer.clearOptions =
                sceneView.renderer.clearOptions.apply {
                    clear = true
                }

            runCatching {
                val environment =
                    sceneView.environmentLoader.createKTX1Environment(
                        "environments/neutral/neutral_ibl.ktx",
                        "environments/neutral/neutral_skybox.ktx",
                    )
                sceneView.environment = environment
                // Keep image-based lighting but hide the opaque skybox background.
                sceneView.scene.skybox = null
            }.onFailure {
                Log.w(TAG, "Failed to configure SceneView environment", it)
            }
        }

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
