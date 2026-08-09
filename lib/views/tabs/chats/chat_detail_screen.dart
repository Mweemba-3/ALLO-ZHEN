import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/data/models/message_model.dart';
import 'package:allo_zhen/data/repositories/chat_repository.dart';
import 'package:allo_zhen/views/widgets/whatsapp_chat_bubble.dart';
import 'package:allo_zhen/core/database/sqlite_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:allo_zhen/core/services/notification_service.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class _AudioMessagePlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  final bool isDarkMode;
  final Color bubbleColor;

  const _AudioMessagePlayer({
    required this.url,
    required this.isMe,
    required this.isDarkMode,
    required this.bubbleColor,
  });

  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        if (_isPlaying) _startTimer();
        else _stopTimer();
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
        _stopTimer();
      }
    });
  }

  @override
  void dispose() {
    _stopTimer();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _playPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play(UrlSource(widget.url));
    }
  }

  void _seek(double value) {
    _audioPlayer.seek(Duration(milliseconds: value.toInt()));
  }

  String _format(Duration d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 100.0;
    final curVal = _position.inMilliseconds <= _duration.inMilliseconds
        ? _position.inMilliseconds.toDouble()
        : 0.0;

    final color = widget.isDarkMode ? const Color(0xFF34B7F1) : const Color(0xFF075E54);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 36,
              color: color,
            ),
            onPressed: _playPause,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  min: 0.0,
                  max: maxVal,
                  value: curVal.clamp(0.0, maxVal),
                  onChanged: _seek,
                  activeColor: color,
                  inactiveColor: widget.isDarkMode ? Colors.white24 : Colors.black12,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _format(_position),
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      Text(
                        _duration > Duration.zero ? '-${_format(_duration - _position)}' : '--:--',
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingBar extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final bool isDarkMode;

  const _RecordingBar({
    required this.onCancel,
    required this.onSend,
    required this.isDarkMode,
  });

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  int _recordDuration = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordDuration++;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.redAccent),
          onPressed: widget.onCancel,
        ),
        const SizedBox(width: 8),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
        const SizedBox(width: 4),
        Text(
          '${_recordDuration ~/ 60}:${(_recordDuration % 60).toString().padLeft(2, '0')}',
          style: TextStyle(
            color: widget.isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.send, color: Color(0xFF00A884)),
          onPressed: widget.onSend,
        ),
      ],
    );
  }
}

class ChatDetailScreen extends StatefulWidget {
  final String recipientId;
  final String recipientDisplayName;
  final String? recipientAvatar;

  const ChatDetailScreen({
    super.key,
    required this.recipientId,
    required this.recipientDisplayName,
    this.recipientAvatar,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> with TickerProviderStateMixin {
  final ChatRepository _chatRepo = ChatRepository();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedFilePath;
  
  StreamSubscription? _typingSubscription;
  RealtimeChannel? _typingChannel;
  StreamSubscription? _presenceSubscription;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _peerIsTyping = false;
  bool _isSending = false;
  bool _isDarkMode = false;
  
  bool _peerIsOnline = false;
  String? _peerLastSeen;

  final _refreshController = StreamController<void>.broadcast();

  bool _isUserInteracting = false;
  int _previousMessageCount = 0;

  String? _wallpaperPath;
  bool _wallpaperLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToTyping();
    _subscribeToPeerPresence();
    _markMessagesAsRead();
    _loadWallpaper();
    
    // ✅ Cancel notification for this chat when opened
    NotificationService.instance.cancelNotification(widget.recipientId.hashCode);
    
    // ✅ Listen to stream and scroll to bottom when new messages arrive
    _chatRepo.streamMessages(otherUserId: widget.recipientId).listen((messages) {
      if (messages.isNotEmpty && mounted && _scrollController.hasClients) {
        final currentScroll = _scrollController.position.pixels;
        if (currentScroll < 50) {
          _scrollToBottom();
        }
      }
    });
  }

  Future<void> _loadWallpaper() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/chat_wallpaper_${widget.recipientId}.jpg');
      
      if (await file.exists()) {
        setState(() {
          _wallpaperPath = file.path;
          _wallpaperLoading = false;
        });
      } else {
        setState(() => _wallpaperLoading = false);
      }
    } catch (e) {
      setState(() => _wallpaperLoading = false);
    }
  }

  Future<void> _pickWallpaper() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _wallpaperLoading = true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'chat_wallpaper_${widget.recipientId}.jpg';
      final newFile = File('${dir.path}/$fileName');

      if (await newFile.exists()) {
        await newFile.delete();
      }

      await File(image.path).copy(newFile.path);

      setState(() {
        _wallpaperPath = newFile.path;
        _wallpaperLoading = false;
      });

      _showNotification('✅ Wallpaper updated');
    } catch (e) {
      setState(() => _wallpaperLoading = false);
      _showNotification('❌ Failed to set wallpaper', color: Colors.redAccent);
    }
  }

  Future<void> _removeWallpaper() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/chat_wallpaper_${widget.recipientId}.jpg');

      if (await file.exists()) {
        await file.delete();
      }

      setState(() {
        _wallpaperPath = null;
      });

      _showNotification('✅ Wallpaper removed');
    } catch (e) {
      _showNotification('❌ Failed to remove wallpaper', color: Colors.redAccent);
    }
  }

  @override
  void dispose() {
    _refreshController.close();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _typingChannel?.unsubscribe();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _subscribeToTyping() {
    _typingChannel = _chatRepo.subscribeToTypingStatus(
      widget.recipientId,
      onTypingChanged: (isTyping) {
        if (mounted) {
          setState(() {
            _peerIsTyping = isTyping;
          });
        }
      },
    );
  }

  void _subscribeToPeerPresence() {
    _presenceSubscription = _chatRepo.streamUserPresence(widget.recipientId).listen((userData) {
      if (userData != null && mounted) {
        setState(() {
          _peerIsOnline = userData['is_online'] == true;
          _peerLastSeen = userData['last_seen'];
        });
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    await _chatRepo.markMessagesAsRead(widget.recipientId);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    
    // With reverse: true, bottom is at offset 0
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _handleTyping(String text) async {
    if (!_isTyping && text.isNotEmpty) {
      _isTyping = true;
      if (_typingChannel != null) {
        await _chatRepo.sendTypingNotification(_typingChannel!, true);
      }
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () async {
      if (_isTyping) {
        _isTyping = false;
        if (_typingChannel != null) {
          await _chatRepo.sendTypingNotification(_typingChannel!, false);
        }
      }
    });
  }

  void _showNotification(String message, {Color? color}) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: color ?? const Color(0xFF00A884),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(milliseconds: 2500), () {
      overlayEntry.remove();
    });
  }

  Future<void> _deleteMessage(MessageModel message) async {
    try {
      final success = await _chatRepo.deleteMessage(message.id);
      
      if (success) {
        _refreshController.add(null);
        _showNotification('✅ Message deleted');
      } else {
        _showNotification('❌ Failed to delete from server', color: Colors.redAccent);
      }
    } catch (e) {
      _showNotification('❌ Error: ${e.toString()}', color: Colors.redAccent);
    }
  }

  Future<void> _sendMessage({String? mediaUrl, MessageType type = MessageType.text}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && mediaUrl == null) return;
    if (_isSending) return;

    setState(() => _isSending = true);

    if (_isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      if (_typingChannel != null) {
        await _chatRepo.sendTypingNotification(_typingChannel!, false);
      }
    }

    try {
      final String contentToSend = text.isNotEmpty ? text : '';
      _messageController.clear();

      await _chatRepo.sendMessage(
        recipientId: widget.recipientId,
        content: contentToSend,
        type: mediaUrl != null ? type : MessageType.text,
        mediaUrl: mediaUrl,
      );
      
      // ✅ Force refresh the stream by triggering a rebuild
      _refreshController.add(null);
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      debugPrint('Error sending message: $e');
      _showNotification('❌ Failed to send message', color: Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final file = File(image.path);
    setState(() => _isSending = true);
    final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
    setState(() => _isSending = false);
    
    if (url != null) {
      await _sendMessage(mediaUrl: url, type: MessageType.image);
    }
  }

  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'zip'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() => _isSending = true);
        final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
        setState(() => _isSending = false);

        if (url != null) {
          await _sendMessage(mediaUrl: url, type: MessageType.document);
        }
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
    }
  }

  Future<void> _openDocument(String url) async {
    try {
      _showNotification('📄 Downloading document...');
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download file');
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = url.split('/').last.split('?').first;
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      
      await file.writeAsBytes(response.bodyBytes);

      final result = await OpenFilex.open(filePath);
      
      if (result.type != ResultType.done) {
        await file.delete();
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showNotification('❌ Could not open file', color: Colors.redAccent);
        }
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
      _showNotification('❌ Error opening file', color: Colors.redAccent);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordedFilePath = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), 
          path: _recordedFilePath!,
        );
        
        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
    });

    if (path != null) {
      final file = File(path);
      setState(() => _isSending = true);
      final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
      setState(() => _isSending = false);

      if (url != null) {
        await _sendMessage(mediaUrl: url, type: MessageType.audio);
      }
    }
  }

  Future<void> _cancelRecording() async {
    await _audioRecorder.stop();
    if (_recordedFilePath != null) {
      try {
        final file = File(_recordedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    setState(() {
      _isRecording = false;
    });
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.spaceAround,
              children: [
                _buildAttachmentOption(Icons.insert_drive_file, Colors.indigo, 'Document', () {
                  Navigator.pop(context);
                  _pickDocument();
                }),
                _buildAttachmentOption(Icons.camera_alt, Colors.pink, 'Camera', () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.camera);
                  if (image != null) {
                    final file = File(image.path);
                    setState(() => _isSending = true);
                    final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
                    setState(() => _isSending = false);
                    if (url != null) await _sendMessage(mediaUrl: url, type: MessageType.image);
                  }
                }),
                _buildAttachmentOption(Icons.image, Colors.purple, 'Gallery', () {
                  Navigator.pop(context);
                  _pickImage();
                }),
                _buildAttachmentOption(Icons.headphones, Colors.orange, 'Audio', () async {
                  Navigator.pop(context);
                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio);
                  if (result != null && result.files.single.path != null) {
                    final file = File(result.files.single.path!);
                    setState(() => _isSending = true);
                    final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
                    setState(() => _isSending = false);
                    if (url != null) await _sendMessage(mediaUrl: url, type: MessageType.audio);
                  }
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatLastSeen(String? lastSeenIso) {
    if (lastSeenIso == null) return 'offline';
    try {
      final parsed = DateTime.parse(lastSeenIso).toLocal();
      final now = DateTime.now();
      if (parsed.day == now.day) {
        return 'last seen today at ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
      }
      return 'last seen ${parsed.day}/${parsed.month} at ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: _isDarkMode ? const Color(0xFF121B22) : const Color(0xFF075E54),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage: widget.recipientAvatar != null && widget.recipientAvatar!.isNotEmpty
                  ? NetworkImage(widget.recipientAvatar!)
                  : null,
              child: widget.recipientAvatar == null || widget.recipientAvatar!.isEmpty
                  ? Text(
                      widget.recipientDisplayName.isNotEmpty ? widget.recipientDisplayName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientDisplayName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    _peerIsTyping 
                      ? 'typing...' 
                      : (_peerIsOnline ? 'online' : _formatLastSeen(_peerLastSeen)),
                    style: TextStyle(
                      color: _peerIsTyping ? Colors.greenAccent : Colors.white70,
                      fontSize: 12,
                      fontStyle: _peerIsTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () {}),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'view': break;
                case 'media': break;
                case 'wallpaper': _pickWallpaper(); break;
                case 'remove_wallpaper': _removeWallpaper(); break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(value: 'view', child: Text('View Contact')),
              const PopupMenuItem<String>(value: 'media', child: Text('Media, links, and docs')),
              const PopupMenuDivider(),
              if (_wallpaperPath == null)
                const PopupMenuItem<String>(
                  value: 'wallpaper',
                  child: Row(
                    children: [
                      Icon(Icons.wallpaper, size: 20),
                      SizedBox(width: 12),
                      Text('Set Chat Wallpaper'),
                    ],
                  ),
                )
              else ...[
                const PopupMenuItem<String>(
                  value: 'wallpaper',
                  child: Row(
                    children: [
                      Icon(Icons.wallpaper, size: 20),
                      SizedBox(width: 12),
                      Text('Change Wallpaper'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'remove_wallpaper',
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Remove Wallpaper', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Container(
        decoration: _wallpaperPath != null && !_wallpaperLoading
            ? BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(_wallpaperPath!)),
                  fit: BoxFit.cover,
                  opacity: 0.25,
                ),
              )
            : null,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<void>(
                stream: _refreshController.stream,
                builder: (context, refreshSnapshot) {
                  return StreamBuilder<List<MessageModel>>(
                    stream: _chatRepo.streamMessages(otherUserId: widget.recipientId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error loading messages: ${snapshot.error}', 
                            style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black54)),
                        );
                      }

                      final messages = snapshot.data ?? [];

                      if (messages.isEmpty) {
                        return Center(
                          child: Text('No messages yet', 
                            style: TextStyle(color: _isDarkMode ? Colors.white54 : Colors.grey.shade600, fontSize: 14)),
                        );
                      }

                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollStartNotification ||
                              notification is OverscrollNotification ||
                              notification is UserScrollNotification) {
                            _isUserInteracting = true;
                          }
                          if (notification is ScrollEndNotification) {
                            _isUserInteracting = false;
                          }
                          return true;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          reverse: true, // ✅ WhatsApp: new messages at bottom
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            // ✅ Get newest first (bottom to top)
                            final message = messages[messages.length - 1 - index];
                            final isMe = message.senderId == _chatRepo.currentUserId;

                            final Color bubbleColor = _isDarkMode
                                ? (isMe ? const Color(0xFF005C4B) : const Color(0xFF202C33))
                                : (isMe ? const Color(0xFFDCF8C6) : Colors.white);

                            final bool hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
                            final bool hasText = message.content.isNotEmpty && message.content != message.mediaUrl;
                            final bool isDocument = message.type == MessageType.document;
                            final bool isAudio = message.type == MessageType.audio;

                            return KeyedSubtree(
                              key: ValueKey(message.id),
                              child: GestureDetector(
                                onLongPress: () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Delete Message'),
                                      content: const Text('Are you sure you want to delete this message?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(dialogContext);
                                            _deleteMessage(message);
                                          },
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: WhatsAppChatBubble(
                                    isMe: isMe,
                                    bubbleColor: bubbleColor,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 280),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (hasMedia && !isDocument && !isAudio)
                                            GestureDetector(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => Scaffold(
                                                      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
                                                      backgroundColor: Colors.black,
                                                      body: Center(child: InteractiveViewer(child: Image.network(message.mediaUrl!))),
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: EdgeInsets.only(bottom: hasText ? 6 : 0),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.network(
                                                    message.mediaUrl!,
                                                    width: 240,
                                                    height: 240,
                                                    fit: BoxFit.cover,
                                                    loadingBuilder: (context, child, loadingProgress) {
                                                      if (loadingProgress == null) return child;
                                                      return Container(
                                                        width: 240,
                                                        height: 240,
                                                        color: Colors.black12,
                                                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),

                                          if (isDocument && hasMedia)
                                            GestureDetector(
                                              onTap: () => _openDocument(message.mediaUrl!),
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: _isDarkMode ? Colors.black26 : Colors.black12,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.insert_drive_file, size: 32, color: Colors.redAccent),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            message.content.isNotEmpty ? message.content : 'Document File',
                                                            style: TextStyle(
                                                              color: _isDarkMode ? Colors.white : Colors.black87, 
                                                              fontWeight: FontWeight.w600
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                          const SizedBox(height: 2),
                                                          Text(
                                                            'Tap to open',
                                                            style: TextStyle(fontSize: 10, color: _isDarkMode ? Colors.white54 : Colors.grey),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),

                                          if (isAudio && hasMedia)
                                            _AudioMessagePlayer(
                                              url: message.mediaUrl!,
                                              isMe: isMe,
                                              isDarkMode: _isDarkMode,
                                              bubbleColor: bubbleColor,
                                            ),

                                          if (hasText && !isDocument)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 65, bottom: 4),
                                              child: Text(
                                                message.content,
                                                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black87, fontSize: 15),
                                              ),
                                            ),

                                          if (hasText && !isDocument)
                                            Align(
                                              alignment: Alignment.bottomRight,
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                                      style: TextStyle(fontSize: 11, color: _isDarkMode ? Colors.white60 : Colors.black54),
                                                    ),
                                                    if (isMe) ...[
                                                      const SizedBox(width: 3),
                                                      Icon(
                                                        message.isRead ? Icons.done_all : Icons.done,
                                                        size: 14,
                                                        color: message.isRead ? Colors.lightBlueAccent : (_isDarkMode ? Colors.white60 : Colors.black54),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),

                                          if ((hasMedia && !hasText) || isDocument || isAudio)
                                            Align(
                                              alignment: Alignment.bottomRight,
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${message.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${message.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                                      style: TextStyle(fontSize: 11, color: _isDarkMode ? Colors.white60 : Colors.black54),
                                                    ),
                                                    if (isMe) ...[
                                                      const SizedBox(width: 3),
                                                      Icon(
                                                        message.isRead ? Icons.done_all : Icons.done,
                                                        size: 14,
                                                        color: message.isRead ? Colors.lightBlueAccent : (_isDarkMode ? Colors.white60 : Colors.black54),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            // --- WhatsApp Style Input Area ---
            Container(
              color: _isDarkMode ? const Color(0xFF1F2C34) : const Color(0xFFF0F0F0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: SafeArea(
                child: _isRecording
                    ? _RecordingBar(
                        isDarkMode: _isDarkMode,
                        onCancel: _cancelRecording,
                        onSend: _stopAndSendRecording,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: _isDarkMode ? const Color(0xFF2A3942) : Colors.white,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.emoji_emotions_outlined, color: _isDarkMode ? Colors.white70 : Colors.grey.shade600),
                                    onPressed: () {},
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      focusNode: _focusNode,
                                      style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black87),
                                      keyboardType: TextInputType.multiline,
                                      maxLines: 5,
                                      minLines: 1,
                                      onChanged: (text) {
                                        _handleTyping(text);
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Type a message',
                                        hintStyle: TextStyle(color: _isDarkMode ? Colors.white54 : Colors.grey.shade500),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.attach_file, color: _isDarkMode ? Colors.white70 : Colors.grey.shade600),
                                    onPressed: _showAttachmentSheet,
                                  ),
                                  if (_messageController.text.trim().isEmpty)
                                    IconButton(
                                      icon: Icon(Icons.camera_alt, color: _isDarkMode ? Colors.white70 : Colors.grey.shade600),
                                      onPressed: () async {
                                        final picker = ImagePicker();
                                        final XFile? image = await picker.pickImage(source: ImageSource.camera);
                                        if (image != null) {
                                          final file = File(image.path);
                                          setState(() => _isSending = true);
                                          final String? url = await _chatRepo.uploadAttachment(file, 'attachments');
                                          setState(() => _isSending = false);
                                          if (url != null) await _sendMessage(mediaUrl: url, type: MessageType.image);
                                        }
                                      },
                                    ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF00A884),
                            child: IconButton(
                              icon: Icon(
                                _messageController.text.trim().isNotEmpty ? Icons.send : Icons.mic,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () {
                                if (_messageController.text.trim().isNotEmpty) {
                                  _sendMessage();
                                } else {
                                  _startRecording();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}