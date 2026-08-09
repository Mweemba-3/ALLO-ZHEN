import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/data/repositories/status_repository.dart';
import 'package:allo_zhen/data/models/status_model.dart';
import 'package:allo_zhen/views/widgets/video_trimmer_screen.dart';
import 'status_view_screen.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  final StatusRepository _statusRepo = StatusRepository();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  List<StatusModel> _statuses = [];

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    try {
      final data = await Supabase.instance.client
          .from('status_updates')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      final allStatuses = data.map((json) => StatusModel.fromMap(json)).toList();
      final filtered = allStatuses
          .where((status) => status.expiresAt.isAfter(DateTime.now()))
          .toList();

      if (mounted) {
        setState(() {
          _statuses = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 80);
    if (image == null) return;

    _showPostingDialog(File(image.path), mediaType: 'image');
  }

  Future<void> _handlePickVideo(ImageSource source) async {
    final XFile? video = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    if (video == null) return;

    final File videoFile = File(video.path);

    final trimmedFile = await Navigator.push<File?>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoTrimmerScreen(videoFile: videoFile, maxDuration: 30),
      ),
    );

    if (trimmedFile != null) {
      _showPostingDialog(trimmedFile, mediaType: 'video');
    }
  }

  void _showPostingDialog(File? mediaFile, {required String mediaType}) {
    final TextEditingController captionController = TextEditingController();
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
                  top: 20,
                  left: 20,
                  right: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaType == 'video'
                          ? 'Post Video Status'
                          : mediaType == 'image'
                              ? 'Post Photo Status'
                              : 'Create Status Update',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (mediaFile != null) ...[
                      Container(
                        height: 140,
                        width: double.infinity,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: mediaType == 'image'
                            ? Image.file(mediaFile, fit: BoxFit.cover)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.videocam_rounded, color: AppColors.primary, size: 32),
                                  SizedBox(width: 8),
                                  Text('Video Ready (≤ 30s)', style: TextStyle(color: Colors.white)),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: captionController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: "Add a caption...",
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isUploading ? null : () => Navigator.pop(modalContext),
                          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: isUploading
                              ? null
                              : () async {
                                  setModalState(() => isUploading = true);

                                  try {
                                    String? uploadedUrl;
                                    if (mediaFile != null) {
                                      uploadedUrl = await _statusRepo.uploadMedia(mediaFile);
                                    }

                                    final text = captionController.text.trim();
                                    if (text.isNotEmpty || uploadedUrl != null) {
                                      await _statusRepo.postStatus(
                                        caption: text,
                                        mediaUrl: uploadedUrl,
                                        mediaType: mediaType,
                                      );
                                    }

                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                  } catch (e) {
                                    if (modalContext.mounted) {
                                      setModalState(() => isUploading = false);
                                      ScaffoldMessenger.of(modalContext).showSnackBar(
                                        SnackBar(content: Text('Failed to post status: $e')),
                                      );
                                    }
                                  }
                                },
                          child: isUploading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Post', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMediaPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.text_fields_rounded, color: AppColors.primary),
                title: const Text('Text Status', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _showPostingDialog(null, mediaType: 'text');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: const Text('Photo from Gallery', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handlePickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: const Text('Take Photo', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handlePickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                title: const Text('Video from Gallery (Max 30s)', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handlePickVideo(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              onTap: _showMediaPickerOptions,
              leading: Stack(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface,
                    child: Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 28),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
              title: const Text(
                'My Status',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Tap to add status update',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.05), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Recent updates',
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_statuses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No recent status updates',
                    style: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 13),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _statuses.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 80,
                  endIndent: 16,
                  color: Colors.white.withOpacity(0.03),
                ),
                itemBuilder: (context, index) {
                  final status = _statuses[index];

                  final isViewed = status.viewedBy.contains(currentUserId);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    onTap: () {
                      // Show all statuses from this user
                      final userStatuses = _statuses
                          .where((s) => s.userId == status.userId)
                          .toList();

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StatusViewScreen(
                            statuses: userStatuses,
                            initialIndex: 0,
                          ),
                        ),
                      );
                    },
                    leading: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isViewed ? Colors.blue.withOpacity(0.6) : AppColors.primary,
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 23,
                        backgroundColor: AppColors.surface,
                        backgroundImage: status.userAvatar != null && status.userAvatar!.isNotEmpty
                            ? NetworkImage(status.userAvatar!)
                            : null,
                        child: status.userAvatar == null || status.userAvatar!.isEmpty
                            ? Text(
                                status.userName.isNotEmpty ? status.userName[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                    title: Text(
                      status.userName,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _formatTimestamp(status.createdAt),
                      style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 12),
                    ),
                    trailing: Text(
                      '${_statuses.where((s) => s.userId == status.userId).length} updates',
                      style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5), fontSize: 12),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'textStatusBtn',
            backgroundColor: AppColors.surface,
            elevation: 2,
            onPressed: () => _showPostingDialog(null, mediaType: 'text'),
            child: const Icon(Icons.edit_rounded, color: AppColors.textPrimary, size: 20),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'cameraStatusBtn',
            backgroundColor: AppColors.primary,
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onPressed: _showMediaPickerOptions,
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}