import 'package:flutter/material.dart';
import 'package:video_mobile_player/video_mobile_player.dart';

void main() => runApp(const PlayerExampleApp());

class PlayerExampleApp extends StatefulWidget {
  const PlayerExampleApp({super.key});

  @override
  State<PlayerExampleApp> createState() => _PlayerExampleAppState();
}

class _PlayerExampleAppState extends State<PlayerExampleApp> {
  final controller = VideoMobilePlayerController();
  static const source = VideoPlayerSource.network(
    'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    title: 'Big Buck Bunny',
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      appBar: AppBar(title: const Text('Video Mobile Player')),
      body: Column(
        children: <Widget>[
          VideoMobilePlayer(controller: controller, source: source),
          StreamBuilder<VideoPlayerState>(
            stream: controller.states,
            builder: (context, snapshot) {
              final state = snapshot.data;
              return Text(
                state == null
                    ? 'Waiting for player'
                    : '${state.status.name}  ${state.position.inSeconds}s  '
                          '${state.networkSpeedBytesPerSecond ~/ 1024} KB/s',
              );
            },
          ),
          Wrap(
            children: <Widget>[
              IconButton(
                onPressed: controller.play,
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                onPressed: controller.pause,
                icon: const Icon(Icons.pause),
              ),
              IconButton(
                onPressed: () => controller.seekBy(const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10),
              ),
              IconButton(
                onPressed: () =>
                    controller.requestMode(VideoPresentationMode.fullscreen),
                icon: const Icon(Icons.fullscreen),
              ),
              IconButton(
                onPressed: () =>
                    controller.requestMode(VideoPresentationMode.floating),
                icon: const Icon(Icons.picture_in_picture),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
