package io.github.onyou668.video_mobile_player

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.github.mobileplayer.core.AppPrivateVideoPlayerCache

class VideoMobilePlayerPlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null
    private var cache: AppPrivateVideoPlayerCache? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val sharedCache = AppPrivateVideoPlayerCache(binding.applicationContext)
        cache = sharedCache
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            VideoPlayerViewFactory(
                messenger = binding.binaryMessenger,
                activityProvider = { activity },
                cache = sharedCache,
            ),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cache?.close()
        cache = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private companion object {
        const val VIEW_TYPE = "io.github.onyou668/video_mobile_player"
    }
}
