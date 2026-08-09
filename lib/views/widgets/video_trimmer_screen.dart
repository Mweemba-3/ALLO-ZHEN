import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';

class VideoTrimmerScreen extends StatefulWidget {
  final File videoFile;
  final int maxDuration; // in seconds

  const VideoTrimmerScreen({
    super.key,
    required this.videoFile,
    this.maxDuration = 30,
  });

  @override
  State<VideoTrimmerScreen> createState() => _VideoTrimmerScreenState();
}

class _VideoTrimmerScreenState extends State<VideoTrimmerScreen> {
  VideoPlayerController? _controller;
  bool _isLoaded = false;
  double _startPosition = 0.0;
  double _endPosition = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() => _isLoaded = true);
        _controller?.play();
        _controller?.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  void _trimVideo() async {
    // In a real app, you'd use FFmpeg or a native trimmer here.
    // For now, we return the original file (since we limited picker to 30s).
    Navigator.pop(context, widget.videoFile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trim Video', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _trimVideo,
            child: const Text('Done', style: TextStyle(color: AppColors.primary, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoaded && _controller != null
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                const Text(
                  'Drag to trim (max 30 seconds)',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (_isLoaded)
                  Row(
                    children: [
                      Text(
                        _formatDuration(_startPosition * _controller!.value.duration.inSeconds),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: _startPosition,
                          onChanged: (val) {
                            setState(() => _startPosition = val);
                            if (_controller != null) {
                              _controller!.seekTo(Duration(seconds: (val * _controller!.value.duration.inSeconds).toInt()));
                            }
                          },
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.grey,
                        ),
                      ),
                      Text(
                        _formatDuration(_endPosition * _controller!.value.duration.inSeconds),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final int mins = (seconds / 60).floor();
    final int secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}