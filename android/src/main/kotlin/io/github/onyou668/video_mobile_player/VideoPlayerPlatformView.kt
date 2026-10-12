package io.github.onyou668.video_mobile_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.ActivityInfo
import android.os.Build
import android.view.View
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.github.mobileplayer.compose.VideoPlayer
import io.github.mobileplayer.compose.VideoPlayerUiConfig
import io.github.mobileplayer.compose.createDefaultVideoPlayerController
import io.github.mobileplayer.core.PlaybackState
import io.github.mobileplayer.core.PlayerEngineType
import io.github.mobileplayer.core.PlayerPresentationController
import io.github.mobileplayer.core.PlayerPresentationMode
import io.github.mobileplayer.core.PlayerPresentationRequest
import io.github.mobileplayer.core.PlayerPresentationState
import io.github.mobileplayer.core.VideoSource
import io.github.mobileplayer.core.VideoPlayerCache
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
    cache: VideoPlayerCache,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val channel = MethodChannel(messenger, "video_mobile_player/view_$viewId")
    private val player = createDefaultVideoPlayerController(
        context = context,
        scope = scope,
        initialEngine = creationParams.engineType(),
        cache = cache,
    )
    private val presentation = PlayerPresentationController(
        startupMode = creationParams.presentationMode(),
    )
    private val composeView = ComposeView(context).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindowOrReleasedFromPool)
        setContent {
            VideoPlayer(
                controller = player,
                presentationController = presentation,
                uiConfig = creationParams.uiConfig(),
            )
        }
    }

    init {
        channel.setMethodCallHandler(this)
        creationParams.source()?.let { source ->
            player.setMedia(
                source = source,
                playWhenReady = creationParams["autoPlay"] as? Boolean ?: true,
            )
        }
        observeState()
        handlePresentationRequests()
    }

    override fun getView(): View = composeView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        runCatching {
            when (call.method) {
                "setSource" -> player.setMedia(
                    source = call.arguments.asStringMap().source()
                        ?: error("setSource requires a non-empty uri"),
                    playWhenReady = call.argument<Boolean>("autoPlay") ?: true,
                )
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
                "getPresentationState" -> return result.success(presentation.state.value.toMap())
                "requestMode" -> return result.success(
                    presentation.requestMode(call.stringArgument("mode").toPresentationMode()),
                )
                "returnFromFloating" -> return result.success(presentation.requestReturnFromFloating())
                "syncPresentationMode" -> presentation.confirmMode(
                    call.stringArgument("mode").toPresentationMode(),
                )
                "close" -> return result.success(presentation.requestClose())
                else -> return result.notImplemented()
            }
            result.success(null)
        }.onFailure { error ->
            result.error("video_mobile_player", error.message, null)
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        composeView.disposeComposition()
        player.close()
        scope.cancel()
    }

    private fun observeState() {
        scope.launch {
            player.state.collectLatest { state ->
                channel.invokeMethod("stateChanged", state.toMap())
            }
        }
        scope.launch {
            presentation.state.collectLatest { state ->
                channel.invokeMethod("presentationChanged", state.toMap())
            }
        }
    }

    private fun handlePresentationRequests() {
        scope.launch {
            presentation.requests.collectLatest { request ->
                when (request) {
                    is PlayerPresentationRequest.ChangeMode -> changeMode(request.to)
                    PlayerPresentationRequest.Close -> {
                        presentation.confirmClosed()
                        channel.invokeMethod("closeRequested", null)
                    }
                }
            }
        }
    }

    private fun changeMode(mode: PlayerPresentationMode) {
        val activity = activityProvider()
        if (activity == null) {
            presentation.rejectPendingRequest("No Activity is attached")
            return
        }
        when (mode) {
            PlayerPresentationMode.INLINE -> {
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                presentation.confirmMode(mode)
            }
            PlayerPresentationMode.FULLSCREEN -> {
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                presentation.confirmMode(mode)
            }
            PlayerPresentationMode.FLOATING -> {
                val entered = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    activity.enterPictureInPictureMode(PictureInPictureParams.Builder().build())
                if (entered) {
                    presentation.confirmMode(mode)
                } else {
                    presentation.rejectPendingRequest("Picture-in-picture is unavailable")
                }
            }
        }
    }
}

private fun Map<String, Any?>.source(): VideoSource? {
    val uri = this["uri"] as? String ?: return null
    if (uri.isBlank()) return null
    val title = this["title"] as? String
    val headers = (this["headers"] as? Map<*, *>)
        ?.entries
        ?.associate { (key, value) -> key.toString() to value.toString() }
        .orEmpty()
    return if (this["sourceType"] == "local") {
        VideoSource.local(uri = uri, title = title)
    } else {
        VideoSource.network(
            url = uri,
            headers = headers,
            title = title,
            contentCachePolicy = if (this["contentCachePolicy"] == "disabled") {
                VideoSource.ContentCachePolicy.DISABLED
            } else {
                VideoSource.ContentCachePolicy.AUTO
            },
        )
    }
}

private fun Map<String, Any?>.engineType(): PlayerEngineType =
    (this["engine"] as? String).toEngineType()

private fun String?.toEngineType(): PlayerEngineType =
    if (this?.lowercase() == "ijk") PlayerEngineType.IJK else PlayerEngineType.MEDIA3

private fun Map<String, Any?>.presentationMode(): PlayerPresentationMode =
    (this["startupMode"] as? String).toPresentationMode()

private fun String?.toPresentationMode(): PlayerPresentationMode = when (this?.lowercase()) {
    "fullscreen" -> PlayerPresentationMode.FULLSCREEN
    "floating" -> PlayerPresentationMode.FLOATING
    else -> PlayerPresentationMode.INLINE
}

private fun Map<String, Any?>.uiConfig(): VideoPlayerUiConfig = VideoPlayerUiConfig(
    showEngineSwitcher = this["showEngineSwitcher"] as? Boolean ?: true,
    showPresentationControls = this["showPresentationControls"] as? Boolean ?: true,
    showNetworkSpeedWhileLoading = this["showNetworkSpeedWhileLoading"] as? Boolean ?: true,
)

private fun MethodCall.longArgument(name: String): Long =
    (argument<Number>(name) ?: error("$name is required")).toLong()

private fun MethodCall.numberArgument(name: String): Number =
    argument<Number>(name) ?: error("$name is required")

private fun MethodCall.stringArgument(name: String): String =
    argument<String>(name) ?: error("$name is required")

private fun PlaybackState.toMap(): Map<String, Any?> = mapOf(
    "engine" to engineType.name.lowercase(),
    "status" to status.name.lowercase(),
    "isPlaying" to isPlaying,
    "positionMs" to positionMs,
    "durationMs" to durationMs,
    "bufferedPositionMs" to bufferedPositionMs,
    "networkSpeedBytesPerSecond" to networkSpeedBytesPerSecond,
    "videoWidth" to videoWidth,
    "videoHeight" to videoHeight,
    "volume" to volume.toDouble(),
    "playbackSpeed" to playbackSpeed.toDouble(),
    "error" to error?.message,
)

private fun PlayerPresentationState.toMap(): Map<String, Any?> = mapOf(
    "currentMode" to currentMode.name.lowercase(),
    "displayedMode" to displayedMode.name.lowercase(),
    "floatingReturnMode" to floatingReturnMode.name.lowercase(),
    "hasPendingRequest" to hasPendingRequest,
    "isClosed" to isClosed,
    "lastFailure" to lastFailure,
)
