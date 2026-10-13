package io.github.onyou668.video_mobile_player

import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.github.mobileplayer.core.VideoContentCache

internal class VideoPlayerViewFactory(
    private val messenger: BinaryMessenger,
    private val activityProvider: () -> Activity?,
    private val cache: VideoContentCache,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        VideoPlayerPlatformView(
            context = context,
            viewId = viewId,
            creationParams = args.asStringMap(),
            messenger = messenger,
            activityProvider = activityProvider,
            cache = cache,
        )
}

internal fun Any?.asStringMap(): Map<String, Any?> =
    (this as? Map<*, *>)
        ?.entries
        ?.associate { (key, value) -> key.toString() to value }
        .orEmpty()
