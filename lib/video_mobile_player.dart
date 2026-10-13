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
      child: PlatformViewLink(
        viewType: 'io.github.onyou668/video_mobile_player',
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) {
          final controller = PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: params.viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: null,
          );
          controller.addOnPlatformViewCreatedListener(
            widget.controller._attach,
          );
          controller.create();
          return controller;
        },
      ),
    );
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
