package io.github.onyou668.video_mobile_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.os.Build
import android.view.View
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.AndroidUiDispatcher
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.github.mobileplayer.compose.LandscapeVideoPlayer
import io.github.mobileplayer.compose.VideoPlayerUiConfig
import io.github.mobileplayer.compose.createDefaultVideoPlayerController
import io.github.mobileplayer.core.PlaybackState
import io.github.mobileplayer.core.PlayerEngineType
import io.github.mobileplayer.core.VideoContentCache
import io.github.mobileplayer.core.VideoPlayerController
import io.github.mobileplayer.core.VideoSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

internal class VideoPlayerPlatformView(
    context: Context,
    viewId: Int,
    creationParams: Map<String, Any?>,
    messenger: BinaryMessenger,
    private val activityProvider: () -> Activity?,
    cache: VideoContentCache,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    // Keep AndroidUiDispatcher last so its dispatcher and frame clock are retained.
    private val recomposer = Recomposer(scope.coroutineContext + AndroidUiDispatcher.Main)
    private val lifecycleOwner = object : SavedStateRegistryOwner {
        override val lifecycle = LifecycleRegistry(this)
        private val savedStateController = SavedStateRegistryController.create(this)
        override val savedStateRegistry get() = savedStateController.savedStateRegistry
    }
    private val channel = MethodChannel(messenger, "video_mobile_player/view_$viewId")
    private val player: VideoPlayerController = createDefaultVideoPlayerController(
        context = context,
        scope = scope,
        initialEngine = creationParams.engineType(),
        cache = cache,
    )
    private val fullscreen = mutableStateOf(creationParams.startupMode() == "fullscreen")
    private var currentMode = creationParams.startupMode().normalizedMode()
    private var floatingReturnMode = if (currentMode == "fullscreen") "fullscreen" else "inline"
    private var closed = false
    private val uiConfig = mutableStateOf(creationParams.uiConfig())
    private val composeView = ComposeView(context).apply {
        // Flutter's texture PlatformView has no AndroidX lifecycle owner in its view tree.
        setViewTreeLifecycleOwner(lifecycleOwner)
        setViewTreeSavedStateRegistryOwner(lifecycleOwner)
        setParentCompositionContext(recomposer)
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindowOrReleasedFromPool)
        setContent {
            LandscapeVideoPlayer(
                controller = player,
                isFullscreen = fullscreen.value,
                onFullscreenChange = { setPresentationMode(if (it) "fullscreen" else "inline") },
                uiConfig = uiConfig.value,
            )
        }
    }

    init {
        lifecycleOwner.lifecycle.currentState = Lifecycle.State.RESUMED
        scope.launch(AndroidUiDispatcher.Main) { recomposer.runRecomposeAndApplyChanges() }
        channel.setMethodCallHandler(this)
        creationParams.source()?.let { source ->
            player.setMedia(
                source = source,
                playWhenReady = creationParams["autoPlay"] as? Boolean ?: true,
                startPositionMs = creationParams.startPositionMs(),
            )
        }
        observeState()
        emitPresentationState()
    }

    override fun getView(): View = composeView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        runCatching {
            when (call.method) {
                "setSource" -> {
                    val args = call.arguments.asStringMap()
                    player.setMedia(
                        source = args.source() ?: error("setSource requires a non-empty uri"),
                        playWhenReady = call.argument<Boolean>("autoPlay") ?: true,
                        startPositionMs = args.startPositionMs(),
                    )
                }
                "play" -> player.play()
                "pause" -> player.pause()
                "togglePlayPause" -> player.togglePlayPause()
                "seekTo" -> player.seekTo(call.longArgument("positionMs"))
                "seekBy" -> player.seekBy(call.longArgument("offsetMs"))
                "setVolume" -> player.setVolume(call.numberArgument("volume").toFloat())
                "setPlaybackSpeed" -> player.setPlaybackSpeed(call.numberArgument("speed").toFloat())
                "switchEngine" -> player.switchEngine(call.stringArgument("engine").toEngineType())
                "retry" -> player.retry()
                "getState" -> return result.success(player.state.value.toMap())
                "getPresentationState" -> return result.success(presentationMap())
                "requestMode" -> return result.success(setPresentationMode(call.stringArgument("mode")))
                "returnFromFloating" -> return result.success(returnFromFloating())
                "syncPresentationMode" -> setPresentationMode(call.stringArgument("mode"))
                "close" -> {
                    closed = true
                    emitPresentationState()
                    channel.invokeMethod("closeRequested", null)
                    return result.success(true)
                }
                else -> return result.notImplemented()
            }
            result.success(null)
        }.onFailure { error -> result.error("video_mobile_player", error.message, null) }
    }

    override fun dispose() {
        closed = true
        lifecycleOwner.lifecycle.currentState = Lifecycle.State.DESTROYED
        channel.setMethodCallHandler(null)
        composeView.disposeComposition()
        recomposer.close()
        player.close()
        scope.cancel()
    }

    private fun observeState() {
        scope.launch { player.state.collectLatest { channel.invokeMethod("stateChanged", it.toMap()) } }
    }

    private fun setPresentationMode(requested: String): Boolean {
        val mode = requested.normalizedMode()
        if (mode == "floating") {
            val activity = activityProvider()
            val entered = activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                activity.enterPictureInPictureMode(PictureInPictureParams.Builder().build())
            if (!entered) return false
            floatingReturnMode = if (currentMode == "fullscreen") "fullscreen" else "inline"
            fullscreen.value = false
            currentMode = "floating"
        } else {
            fullscreen.value = mode == "fullscreen"
            currentMode = mode
        }
        emitPresentationState()
        return true
    }

    private fun returnFromFloating(): Boolean {
        if (currentMode != "floating") return false
        fullscreen.value = floatingReturnMode == "fullscreen"
        currentMode = floatingReturnMode
        emitPresentationState()
        return true
    }

    private fun emitPresentationState() {
        if (!closed) channel.invokeMethod("presentationChanged", presentationMap())
    }

    private fun presentationMap(): Map<String, Any?> = mapOf(
        "currentMode" to currentMode,
        "displayedMode" to currentMode,
        "floatingReturnMode" to floatingReturnMode,
        "hasPendingRequest" to false,
        "isClosed" to closed,
        "lastFailure" to null,
    )
}

private fun Map<String, Any?>.source(): VideoSource? {
    val uri = this["uri"] as? String ?: return null
    if (uri.isBlank()) return null
    val title = this["title"] as? String
    val headers = (this["headers"] as? Map<*, *>)
        ?.entries?.associate { (key, value) -> key.toString() to value.toString() }.orEmpty()
    return if (this["sourceType"] == "local") {
        VideoSource.local(uri = uri, title = title)
    } else {
        VideoSource.network(
            url = uri,
            headers = headers,
            title = title,
            contentCachePolicy = if (this["contentCachePolicy"] == "disabled") {
                VideoSource.ContentCachePolicy.DISABLED
            } else VideoSource.ContentCachePolicy.AUTO,
        )
    }
}

private fun Map<String, Any?>.startPositionMs(): Long = (this["startPositionMs"] as? Number)?.toLong() ?: 0L
private fun Map<String, Any?>.engineType(): PlayerEngineType = (this["engine"] as? String).toEngineType()
private fun String?.toEngineType(): PlayerEngineType = if (this?.lowercase() == "ijk") PlayerEngineType.IJK else PlayerEngineType.MEDIA3
private fun Map<String, Any?>.startupMode(): String = (this["startupMode"] as? String).orEmpty()
private fun String.normalizedMode(): String = when (lowercase()) {
    "fullscreen" -> "fullscreen"
    "floating" -> "floating"
    else -> "inline"
}
private fun Map<String, Any?>.uiConfig(): VideoPlayerUiConfig = VideoPlayerUiConfig(
    showEngineSwitcher = this["showEngineSwitcher"] as? Boolean ?: true,
    showNetworkSpeedWhileLoading = this["showNetworkSpeedWhileLoading"] as? Boolean ?: true,
)
private fun MethodCall.longArgument(name: String): Long = (argument<Number>(name) ?: error("$name is required")).toLong()
private fun MethodCall.numberArgument(name: String): Number = argument<Number>(name) ?: error("$name is required")
private fun MethodCall.stringArgument(name: String): String = argument<String>(name) ?: error("$name is required")

private fun PlaybackState.toMap(): Map<String, Any?> = mapOf(
    "engine" to engineType.name.lowercase(), "status" to status.name.lowercase(),
    "isPlaying" to isPlaying, "positionMs" to positionMs, "durationMs" to durationMs,
    "bufferedPositionMs" to bufferedPositionMs,
    "networkSpeedBytesPerSecond" to networkSpeedBytesPerSecond,
    "videoWidth" to videoWidth, "videoHeight" to videoHeight,
    "volume" to volume.toDouble(), "playbackSpeed" to playbackSpeed.toDouble(),
    "error" to error?.message,
)
