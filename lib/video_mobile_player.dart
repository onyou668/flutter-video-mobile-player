import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

enum VideoPlayerEngine { media3, ijk }

enum VideoPresentationMode { inline, fullscreen, floating }

enum VideoPlaybackStatus { idle, preparing, ready, buffering, ended, error }

enum VideoContentCachePolicy { auto, disabled }

@immutable
class VideoPlayerSource {
  const VideoPlayerSource.network(
    this.uri, {
    this.headers = const <String, String>{},
    this.title,
    this.contentCachePolicy = VideoContentCachePolicy.auto,
  }) : isLocal = false;

  const VideoPlayerSource.local(this.uri, {this.title})
    : isLocal = true,
      headers = const <String, String>{},
      contentCachePolicy = VideoContentCachePolicy.disabled;

  final String uri;
  final bool isLocal;
  final Map<String, String> headers;
  final String? title;
  final VideoContentCachePolicy contentCachePolicy;

  Map<String, Object?> toMap() => <String, Object?>{
    'uri': uri,
    'sourceType': isLocal ? 'local' : 'network',
    'headers': headers,
    'title': title,
    'contentCachePolicy': contentCachePolicy.name,
  };

  @override
  bool operator ==(Object other) =>
      other is VideoPlayerSource &&
      uri == other.uri &&
      isLocal == other.isLocal &&
      title == other.title &&
      contentCachePolicy == other.contentCachePolicy &&
      mapEquals(headers, other.headers);

  @override
  int get hashCode => Object.hash(
    uri,
    isLocal,
    title,
    contentCachePolicy,
    Object.hashAll(headers.entries),
  );
}

@immutable
class VideoPlayerState {
  const VideoPlayerState({
    required this.engine,
    required this.status,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.networkSpeedBytesPerSecond,
    required this.videoWidth,
    required this.videoHeight,
    required this.volume,
    required this.playbackSpeed,
    this.error,
  });

  factory VideoPlayerState.fromMap(
    Map<Object?, Object?> map,
  ) => VideoPlayerState(
    engine:
        _enumByName(VideoPlayerEngine.values, map['engine']) ??
        VideoPlayerEngine.media3,
    status:
        _enumByName(VideoPlaybackStatus.values, map['status']) ??
        VideoPlaybackStatus.idle,
    isPlaying: map['isPlaying'] as bool? ?? false,
    position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
    duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
    bufferedPosition: Duration(
      milliseconds: (map['bufferedPositionMs'] as num?)?.toInt() ?? 0,
    ),
    networkSpeedBytesPerSecond:
        (map['networkSpeedBytesPerSecond'] as num?)?.toInt() ?? 0,
    videoWidth: (map['videoWidth'] as num?)?.toInt() ?? 0,
    videoHeight: (map['videoHeight'] as num?)?.toInt() ?? 0,
    volume: (map['volume'] as num?)?.toDouble() ?? 1,
    playbackSpeed: (map['playbackSpeed'] as num?)?.toDouble() ?? 1,
    error: map['error'] as String?,
  );

  final VideoPlayerEngine engine;
  final VideoPlaybackStatus status;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final int networkSpeedBytesPerSecond;
  final int videoWidth;
  final int videoHeight;
  final double volume;
  final double playbackSpeed;
  final String? error;
}

@immutable
class VideoPresentationState {
  const VideoPresentationState({
    required this.currentMode,
    required this.displayedMode,
    required this.floatingReturnMode,
    required this.hasPendingRequest,
    required this.isClosed,
    this.lastFailure,
  });

  factory VideoPresentationState.fromMap(Map<Object?, Object?> map) =>
      VideoPresentationState(
        currentMode:
            _enumByName(VideoPresentationMode.values, map['currentMode']) ??
            VideoPresentationMode.inline,
        displayedMode:
            _enumByName(VideoPresentationMode.values, map['displayedMode']) ??
            VideoPresentationMode.inline,
        floatingReturnMode:
            _enumByName(
              VideoPresentationMode.values,
              map['floatingReturnMode'],
            ) ??
            VideoPresentationMode.inline,
        hasPendingRequest: map['hasPendingRequest'] as bool? ?? false,
        isClosed: map['isClosed'] as bool? ?? false,
        lastFailure: map['lastFailure'] as String?,
      );

  final VideoPresentationMode currentMode;
  final VideoPresentationMode displayedMode;
  final VideoPresentationMode floatingReturnMode;
  final bool hasPendingRequest;
  final bool isClosed;
  final String? lastFailure;
}

class VideoMobilePlayerController {
  MethodChannel? _channel;
  bool _disposed = false;
  final StreamController<VideoPlayerState> _states =
      StreamController.broadcast();
  final StreamController<VideoPresentationState> _presentationStates =
      StreamController.broadcast();
  final StreamController<void> _closeRequests = StreamController.broadcast();

  Stream<VideoPlayerState> get states => _states.stream;
  Stream<VideoPresentationState> get presentationStates =>
      _presentationStates.stream;
  Stream<void> get closeRequests => _closeRequests.stream;

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> togglePlayPause() => _invoke('togglePlayPause');
  Future<void> retry() => _invoke('retry');
  Future<void> seekTo(Duration position) => _invoke('seekTo', <String, Object>{
    'positionMs': position.inMilliseconds,
  });
  Future<void> seekBy(Duration offset) =>
      _invoke('seekBy', <String, Object>{'offsetMs': offset.inMilliseconds});
  Future<void> setVolume(double volume) =>
      _invoke('setVolume', <String, Object>{'volume': volume});
  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', <String, Object>{'speed': speed});
  Future<void> switchEngine(VideoPlayerEngine engine) =>
      _invoke('switchEngine', <String, Object>{'engine': engine.name});

  Future<void> setSource(
    VideoPlayerSource source, {
    bool autoPlay = true,
    Duration startPosition = Duration.zero,
  }) => _invoke('setSource', <String, Object?>{
    ...source.toMap(),
    'autoPlay': autoPlay,
    'startPositionMs': startPosition.inMilliseconds,
  });

  Future<bool> requestMode(VideoPresentationMode mode) async =>
      await _invoke<bool>('requestMode', <String, Object>{'mode': mode.name}) ??
      false;

  Future<bool> returnFromFloating() async =>
      await _invoke<bool>('returnFromFloating') ?? false;

  Future<void> syncPresentationMode(VideoPresentationMode mode) =>
      _invoke('syncPresentationMode', <String, Object>{'mode': mode.name});

  Future<bool> close() async => await _invoke<bool>('close') ?? false;

  Future<VideoPlayerState> currentState() async {
    final map = await _invoke<Map<Object?, Object?>>('getState') ?? const {};
    return VideoPlayerState.fromMap(map);
  }

  Future<VideoPresentationState> currentPresentationState() async {
    final map =
        await _invoke<Map<Object?, Object?>>('getPresentationState') ??
        const {};
    return VideoPresentationState.fromMap(map);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    _states.close();
    _presentationStates.close();
    _closeRequests.close();
  }

  void _attach(int viewId) {
    if (_disposed) throw StateError('VideoMobilePlayerController is disposed');
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('video_mobile_player/view_$viewId')
      ..setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments;
    switch (call.method) {
      case 'stateChanged':
        if (arguments is Map<Object?, Object?>) {
          _states.add(VideoPlayerState.fromMap(arguments));
        }
      case 'presentationChanged':
        if (arguments is Map<Object?, Object?>) {
          _presentationStates.add(VideoPresentationState.fromMap(arguments));
        }
      case 'closeRequested':
        _closeRequests.add(null);
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) {
    if (_disposed) {
      return Future.error(
        StateError('VideoMobilePlayerController is disposed'),
      );
    }
    final channel = _channel;
    if (channel == null) {
      return Future.error(
        StateError('VideoMobilePlayer is not attached to the controller'),
      );
    }
    return channel.invokeMethod<T>(method, arguments);
  }
}

class VideoMobilePlayer extends StatefulWidget {
  const VideoMobilePlayer({
    required this.source,
    required this.controller,
    this.autoPlay = true,
    this.startPosition = Duration.zero,
    this.aspectRatio = 16 / 9,
    this.initialEngine = VideoPlayerEngine.media3,
    this.startupMode = VideoPresentationMode.inline,
    this.showEngineSwitcher = true,
    this.showNetworkSpeedWhileLoading = true,
    super.key,
  });

  final VideoPlayerSource source;
  final VideoMobilePlayerController controller;
  final bool autoPlay;
  final Duration startPosition;
  final double aspectRatio;
  final VideoPlayerEngine initialEngine;
  final VideoPresentationMode startupMode;
  final bool showEngineSwitcher;
  final bool showNetworkSpeedWhileLoading;

  @override
  State<VideoMobilePlayer> createState() => _VideoMobilePlayerState();
}

class _VideoMobilePlayerState extends State<VideoMobilePlayer> {
  @override
  void didUpdateWidget(VideoMobilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.startPosition != widget.startPosition) {
      widget.controller.setSource(
        widget.source,
        autoPlay: widget.autoPlay,
        startPosition: widget.startPosition,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('video_mobile_player currently supports Android only'),
        ),
      );
    }
    final creationParams = <String, Object?>{
      ...widget.source.toMap(),
      'autoPlay': widget.autoPlay,
      'startPositionMs': widget.startPosition.inMilliseconds,
      'engine': widget.initialEngine.name,
      'startupMode': widget.startupMode.name,
      'showEngineSwitcher': widget.showEngineSwitcher,
      'showNetworkSpeedWhileLoading': widget.showNetworkSpeedWhileLoading,
    };
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlatformViewLink(
            viewType: 'io.github.onyou668/video_mobile_player',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (params) {
              final platformController =
                  PlatformViewsService.initSurfaceAndroidView(
                    id: params.id,
                    viewType: params.viewType,
                    layoutDirection: TextDirection.ltr,
                    creationParams: creationParams,
                    creationParamsCodec: const StandardMessageCodec(),
                    onFocus: null,
                  );
              platformController.addOnPlatformViewCreatedListener(
                widget.controller._attach,
              );
              platformController.create();
              return platformController;
            },
          ),
          StreamBuilder<VideoPlayerState>(
            stream: widget.controller.states,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state == null) return const SizedBox.expand();
              return _FlutterPlayerControls(
                controller: widget.controller,
                source: widget.source,
                state: state,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlutterPlayerControls extends StatefulWidget {
  const _FlutterPlayerControls({
    required this.controller,
    required this.source,
    required this.state,
  });

  final VideoMobilePlayerController controller;
  final VideoPlayerSource source;
  final VideoPlayerState state;

  @override
  State<_FlutterPlayerControls> createState() => _FlutterPlayerControlsState();
}

class _FlutterPlayerControlsState extends State<_FlutterPlayerControls> {
  Timer? _hideTimer;
  bool _visible = true;
  bool _scrubbing = false;
  double _scrubPosition = 0;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(_FlutterPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.isPlaying && !oldWidget.state.isPlaying) _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.state.isPlaying) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _interact() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remaining = seconds % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final duration = state.duration;
    final position = _scrubbing
        ? Duration(milliseconds: _scrubPosition.toInt())
        : state.position;
    final canSeek = duration > Duration.zero;
    final loading =
        state.status == VideoPlaybackStatus.preparing ||
        state.status == VideoPlaybackStatus.buffering;
    final maxMs = duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    final valueMs = position.inMilliseconds
        .toDouble()
        .clamp(0, maxMs)
        .toDouble();
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() => _visible = !_visible);
          if (_visible) _scheduleHide();
        },
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_visible,
            child: Stack(
              children: [
                if (loading)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(
                          '${state.status.name}  ${_formatSpeed(state.networkSpeedBytesPerSecond)}',
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.source.title ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _interact();
                            widget.controller.switchEngine(
                              state.engine == VideoPlayerEngine.media3
                                  ? VideoPlayerEngine.ijk
                                  : VideoPlayerEngine.media3,
                            );
                          },
                          child: Text(
                            state.engine == VideoPlayerEngine.media3
                                ? 'Exo'
                                : 'Ijk',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          _interact();
                          widget.controller.seekBy(
                            const Duration(seconds: -10),
                          );
                        },
                        icon: const Icon(Icons.replay_10),
                      ),
                      IconButton(
                        iconSize: 48,
                        onPressed: () {
                          _interact();
                          widget.controller.togglePlayPause();
                        },
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _interact();
                          widget.controller.seekBy(const Duration(seconds: 10));
                        },
                        icon: const Icon(Icons.forward_10),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: state.volume > 0 ? 'Mute' : 'Unmute',
                          onPressed: () {
                            _interact();
                            widget.controller.setVolume(
                              state.volume > 0 ? 0 : 1,
                            );
                          },
                          icon: Icon(
                            state.volume > 0
                                ? Icons.volume_up
                                : Icons.volume_off,
                          ),
                        ),
                        Text(_time(position)),
                        Expanded(
                          child: Slider(
                            value: valueMs,
                            max: maxMs,
                            onChanged: canSeek
                                ? (value) {
                                    _interact();
                                    setState(() {
                                      _scrubbing = true;
                                      _scrubPosition = value;
                                    });
                                  }
                                : null,
                            onChangeEnd: canSeek
                                ? (value) {
                                    widget.controller.seekTo(
                                      Duration(milliseconds: value.toInt()),
                                    );
                                    setState(() => _scrubbing = false);
                                  }
                                : null,
                          ),
                        ),
                        Text(_time(duration)),
                        TextButton(
                          onPressed: () {
                            _interact();
                            const speeds = <double>[0.75, 1, 1.25, 1.5, 2];
                            final index = speeds.indexOf(state.playbackSpeed);
                            widget.controller.setPlaybackSpeed(
                              speeds[(index + 1) % speeds.length],
                            );
                          },
                          child: Text('${state.playbackSpeed}x'),
                        ),
                        IconButton(
                          tooltip: 'Fullscreen',
                          onPressed: () {
                            _interact();
                            widget.controller.requestMode(
                              VideoPresentationMode.fullscreen,
                            );
                          },
                          icon: const Icon(Icons.fullscreen),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '$bytesPerSecond B/s';
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
