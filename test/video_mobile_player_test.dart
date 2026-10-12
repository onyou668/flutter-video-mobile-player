import 'package:flutter_test/flutter_test.dart';
import 'package:video_mobile_player/video_mobile_player.dart';

void main() {
  test('maps native playback state', () {
    final state = VideoPlayerState.fromMap(<Object?, Object?>{
      'engine': 'ijk',
      'status': 'buffering',
      'isPlaying': false,
      'positionMs': 12000,
      'durationMs': 60000,
      'bufferedPositionMs': 30000,
      'networkSpeedBytesPerSecond': 1048576,
      'videoWidth': 1920,
      'videoHeight': 1080,
      'volume': 0.5,
      'playbackSpeed': 1.25,
    });

    expect(state.engine, VideoPlayerEngine.ijk);
    expect(state.status, VideoPlaybackStatus.buffering);
    expect(state.position, const Duration(seconds: 12));
    expect(state.networkSpeedBytesPerSecond, 1048576);
    expect(state.playbackSpeed, 1.25);
  });

  test('serializes network source', () {
    const source = VideoPlayerSource.network(
      'https://example.com/video.mp4',
      headers: <String, String>{'Authorization': 'token'},
      title: 'Video',
    );

    expect(source.toMap()['sourceType'], 'network');
    expect(source.toMap()['headers'], <String, String>{
      'Authorization': 'token',
    });
    expect(source.toMap().containsKey('mediaId'), isFalse);
    expect(source.toMap()['contentCachePolicy'], 'auto');
  });
}
