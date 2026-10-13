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
    'https://media.w3.org/2010/05/sintel/trailer.mp4',
    title: 'Sintel trailer',
    contentCachePolicy: VideoContentCachePolicy.disabled,
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: VideoMobilePlayer(controller: controller, source: source),
      ),
    ),
  );
}
