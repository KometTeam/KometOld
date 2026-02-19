import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class YAZNAYTVOYTELEFON extends StatefulWidget {
  final String videoPath;

  const YAZNAYTVOYTELEFON({super.key, required this.videoPath});

  @override
  State<YAZNAYTVOYTELEFON> createState() => _YAZNAYTVOYTELEFONState();
}

class _YAZNAYTVOYTELEFONState extends State<YAZNAYTVOYTELEFON> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    
    // Инициализация плеера из assets
    _controller = VideoPlayerController.asset(widget.videoPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
          _controller.setLooping(true); // Зацикливаем видео
        }
      }).catchError((error) {
        print('❌ Ошибка загрузки видео: $error');
        // Показываем чёрный экран даже при ошибке
        if (mounted) {
          setState(() {
            _isInitialized = true; // Показываем чёрный экран
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Блокируем выход
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _isInitialized
              ? _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller), // БЕЗ контролов!
                    )
                  : Container(color: Colors.black) // Чёрный экран при ошибке
              : const CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
