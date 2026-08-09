import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/data/repositories/status_repository.dart';
import 'package:allo_zhen/data/models/status_model.dart';

class StatusViewScreen extends StatefulWidget {
  final List<StatusModel> statuses;
  final int initialIndex;

  const StatusViewScreen({
    super.key,
    required this.statuses,
    this.initialIndex = 0,
  });

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoAdvanceTimer;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isDeleting = false;
  bool _isPaused = false;

  final StatusRepository _statusRepo = StatusRepository();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadMedia(_currentIndex);
    _startAutoAdvance();
    _markCurrentStatusAsViewed();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadMedia(int index) {
    final status = widget.statuses[index];
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;
    _isPaused = false;

    if (status.mediaType == 'video' && status.imageUrl != null && status.imageUrl!.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(status.imageUrl!))
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _isVideoInitialized = true);
            _videoController?.setLooping(false);
            _videoController?.play();
            _videoController?.addListener(() {
              if (_videoController!.value.position >= _videoController!.value.duration) {
                _goToNext();
              }
            });
          }
        });
    }
  }

  void _markCurrentStatusAsViewed() {
    final status = widget.statuses[_currentIndex];
    if (!status.viewedBy.contains(Supabase.instance.client.auth.currentUser?.id)) {
      _statusRepo.markStatusAsViewed(status.id);
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (_isPaused) return;
    if (widget.statuses[_currentIndex].mediaType == 'video') return;
    _autoAdvanceTimer = Timer(const Duration(seconds: 25), () {
      _goToNext();
    });
  }

  void _goToNext() {
    if (_currentIndex < widget.statuses.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _deleteStatus() async {
    final status = widget.statuses[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Status'),
        content: const Text('Are you sure you want to delete this status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      await _statusRepo.deleteStatus(status.id);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete status: $e')),
        );
      }
    }
  }

  void _togglePause() {
    if (_videoController != null && _isVideoInitialized) {
      setState(() {
        _isPaused = !_isPaused;
      });
      if (_isPaused) {
        _videoController?.pause();
        _autoAdvanceTimer?.cancel();
      } else {
        _videoController?.play();
        _startAutoAdvance();
      }
    }
  }

  void _fastForward(double offset) {
    if (_videoController != null && _isVideoInitialized) {
      final currentPos = _videoController!.value.position;
      final duration = _videoController!.value.duration;
      
      Duration seekTo;
      if (offset > 0) {
        seekTo = currentPos + const Duration(seconds: 5);
      } else {
        seekTo = currentPos - const Duration(seconds: 5);
      }

      if (seekTo < Duration.zero) {
        seekTo = Duration.zero;
      } else if (seekTo > duration) {
        seekTo = duration;
      }

      _videoController!.seekTo(seekTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleting) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surface,
              backgroundImage: widget.statuses[_currentIndex].userAvatar != null &&
                      widget.statuses[_currentIndex].userAvatar!.isNotEmpty
                  ? NetworkImage(widget.statuses[_currentIndex].userAvatar!)
                  : null,
              child: widget.statuses[_currentIndex].userAvatar == null ||
                      widget.statuses[_currentIndex].userAvatar!.isEmpty
                  ? Text(
                      widget.statuses[_currentIndex].userName.isNotEmpty
                          ? widget.statuses[_currentIndex].userName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              widget.statuses[_currentIndex].userName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (widget.statuses[_currentIndex].userId ==
              Supabase.instance.client.auth.currentUser?.id)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _deleteStatus,
            ),
        ],
      ),
      body: GestureDetector(
        onTap: _togglePause,
        onLongPressStart: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isLeft = details.localPosition.dx < screenWidth / 2;
          _fastForward(isLeft ? -1 : 1);
        },
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _goToPrevious();
          } else if (details.primaryVelocity! < 0) {
            _goToNext();
          }
        },
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
            _loadMedia(index);
            _startAutoAdvance();
            _markCurrentStatusAsViewed();
          },
          itemCount: widget.statuses.length,
          itemBuilder: (context, index) {
            final status = widget.statuses[index];
            final isLast = index == widget.statuses.length - 1;

            return Stack(
              children: [
                Center(
                  child: status.mediaType == 'video'
                      ? (_isVideoInitialized && _videoController != null
                          ? AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            )
                          : const CircularProgressIndicator(color: AppColors.primary))
                      : (status.mediaType == 'image' &&
                              status.imageUrl != null &&
                              status.imageUrl!.isNotEmpty
                          ? Image.network(
                              status.imageUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Text(
                                status.caption ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )),
                ),
                if (status.mediaType != 'text' &&
                    status.caption != null &&
                    status.caption!.isNotEmpty)
                  Positioned(
                    bottom: 30,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status.caption!,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // Progress indicators
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: widget.statuses.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final isActive = idx == _currentIndex;
                      final isPast = idx < _currentIndex;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : isPast
                                    ? Colors.white.withOpacity(0.5)
                                    : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // "End of statuses" indicator
                if (isLast)
                  Positioned(
                    bottom: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'End of statuses',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                // Pause overlay
                if (_isPaused && _isVideoInitialized)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.pause, color: Colors.white, size: 48),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}