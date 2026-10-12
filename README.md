# video_mobile_player

Flutter Android 视频播放器插件，底层复用 `video-mobile-player` 的 Media3、IjkPlayer、Jetpack Compose UI 和展示模式控制。

当前只支持 Android。播放器源码通过 Git submodule 固定在 `android/video-mobile-player`。

插件 `v0.2.0` 固定使用 Android 播放器主库 `v0.2.0`。调用方只需要依赖本插件 tag，不需要直接管理底层主库版本。

## 获取源码

```shell
git clone --recurse-submodules https://github.com/onyou668/flutter-video-mobile-player.git
```

已有仓库需要初始化：

```shell
git submodule update --init --recursive
```

## 使用

```yaml
dependencies:
  video_mobile_player:
    git:
      url: https://github.com/onyou668/flutter-video-mobile-player.git
      ref: v0.2.0
```

直接使用 Git dependency 时，Dart Pub 不保证自动初始化 submodule。正式使用建议先发布包含已检出 submodule 内容的 pub 包，或将仓库作为本地 path dependency 使用。

```dart
final controller = VideoMobilePlayerController();

const source = VideoPlayerSource.network(
  'https://example.com/video.mp4',
  mediaId: 'movie-42',
  headers: <String, String>{'Authorization': 'Bearer token'},
  title: 'Video',
);

AspectRatio(
  aspectRatio: 16 / 9,
  child: VideoMobilePlayer(
    controller: controller,
    source: source,
    // 非空时优先于本地保存的进度；传 Duration.zero 强制从头播放。
    startPosition: const Duration(minutes: 10),
    initialEngine: VideoPlayerEngine.media3,
    startupMode: VideoPresentationMode.inline,
  ),
)
```

`VideoMobilePlayer` 只是可嵌入的播放器 Widget；详情、剧集、评论和推荐等页面内容始终由 Flutter 宿主实现。宿主可通过同一 `VideoMobilePlayerController` 切换地址、内核和展示模式，播放进度不依赖业务页面。

本地视频使用系统选择器返回的 `content://` URI：

```dart
final source = VideoPlayerSource.local(uri.toString(), title: 'Local video');
```

`mediaId` 是播放进度和视频内容缓存的稳定标识；不传时使用 URI。本地文件只保存进度，不复制视频内容。网络 MP4 等支持 HTTP Range 的渐进式文件会自动边播边缓存，拖动到新位置时只下载对应分段，Media3/Ijk 切换时共用同一份状态和缓存。App 数据清除或卸载后这些数据会被系统删除。

HLS/DASH 不缓存媒体内容。标准 `.m3u8`/`.mpd` URL 会自动绕过；无标准扩展名时显式关闭：

```dart
const live = VideoPlayerSource.network(
  'https://example.com/opaque-live-url',
  mediaId: 'live-channel-1',
  contentCachePolicy: VideoContentCachePolicy.disabled,
);
```

目标 SDK 禁止明文流量时，宿主需要在 Android Network Security Config 中仅允许 `127.0.0.1`/`localhost`，供本地 Range 代理使用；不要全局开放 HTTP。完整配置见底层播放器 [README](android/video-mobile-player/README.md)。

## 控制

```dart
await controller.play();
await controller.pause();
await controller.seekTo(const Duration(seconds: 30));
await controller.seekBy(const Duration(seconds: 10));
await controller.setSource(
  source,
  startPosition: const Duration(minutes: 10),
);
await controller.setVolume(0.5);
await controller.setPlaybackSpeed(1.5);
await controller.switchEngine(VideoPlayerEngine.ijk);
await controller.requestMode(VideoPresentationMode.fullscreen);
await controller.requestMode(VideoPresentationMode.floating);
await controller.returnFromFloating();
```

订阅统一状态：

```dart
controller.states.listen((state) {
  print(state.position);
  print(state.networkSpeedBytesPerSecond);
});

controller.presentationStates.listen((state) {
  print(state.currentMode);
  print(state.floatingReturnMode);
});
```

Widget 销毁后由业务释放 Dart Controller：

```dart
@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

## 扩展

弹幕、字幕、手势层等业务 UI 建议作为 `VideoMobilePlayer` 上方的 Flutter 覆盖层实现，不需要修改播放器内核：

```dart
Stack(
  children: [
    VideoMobilePlayer(controller: controller, source: source),
    Positioned.fill(child: DanmakuOverlay(controller: danmakuController)),
  ],
)
```

通过 `controller.states` 的 `position`、`status` 和 `isPlaying` 驱动覆盖层同步。需要扩展原生 Compose 控制栏、播放内核或展示模式时，在 `android/video-mobile-player` 主库中实现并更新 submodule 指针；Dart 层只负责稳定的命令和状态协议，避免业务 UI 与 Media3/IjkPlayer 直接耦合。

## PiP

宿主 Activity 需要声明：

```xml
<activity
    android:name=".MainActivity"
    android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation"
    android:resizeableActivity="true"
    android:supportsPictureInPicture="true" />
```

系统 PiP 被点击展开后，业务可以同步返回目标模式：

```dart
final presentation = await controller.currentPresentationState();
await controller.syncPresentationMode(presentation.floatingReturnMode);
```

## 更新底层播放器

```shell
git -C android/video-mobile-player fetch --tags
git -C android/video-mobile-player checkout <android-player-tag>
git add android/video-mobile-player
git commit -m "chore: update native player to <android-player-tag>"
```

底层主库变更后，插件必须更新 submodule、通过 CI 并发布新的插件 tag。业务项目始终只依赖插件自己的 tag。

每次更新后执行：

```shell
flutter analyze
flutter test
cd example
flutter build apk --debug
```
