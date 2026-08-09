import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/status_model.dart';

class StatusRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  final _statusController = StreamController<List<StatusModel>>.broadcast();

  StatusRepository() {
    _supabase
        .from('status_updates')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen((data) {
          final allStatuses = data.map((json) => StatusModel.fromMap(json)).toList();
          final filtered = allStatuses
              .where((status) => status.expiresAt.isAfter(DateTime.now()))
              .toList();
          _statusController.add(filtered);
        }, onError: (error) {
          debugPrint('❌ Status stream error: $error');
        });

    _loadInitialStatuses();
  }

  void _loadInitialStatuses() async {
    try {
      final data = await _supabase
          .from('status_updates')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      final allStatuses = data.map((json) => StatusModel.fromMap(json)).toList();
      final filtered = allStatuses
          .where((status) => status.expiresAt.isAfter(DateTime.now()))
          .toList();

      _statusController.add(filtered);
    } catch (e) {
      debugPrint('❌ Error loading initial statuses: $e');
      _statusController.add([]);
    }
  }

  Stream<List<StatusModel>> getActiveStatusesStream() {
    return _statusController.stream;
  }

  Future<String?> uploadMedia(File file) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final storagePath = 'statuses/$fileName';

      await _supabase.storage.from('status_media').upload(storagePath, file);
      return _supabase.storage.from('status_media').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint('Error uploading media: $e');
      return null;
    }
  }

  Future<void> postStatus({
    String? caption,
    String? mediaUrl,
    String mediaType = 'text',
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 24));

    try {
      final profile = await _supabase.from('users').select().eq('id', user.id).maybeSingle();
      final userName = profile != null ? (profile['public_display_name'] ?? 'Allo User') : 'Allo User';
      final userAvatar = profile?['avatar_url'];

      await _supabase.from('status_updates').insert({
        'user_id': user.id,
        'user_name': userName,
        'user_avatar': userAvatar,
        'caption': caption,
        'image_url': mediaUrl,
        'media_type': mediaType,
        'created_at': now.toIso8601String(),
        'expires_at': expires.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error posting status: $e');
    }
  }

  Future<void> deleteFileFromStorage(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      
      final publicIndex = pathSegments.indexOf('public');
      if (publicIndex == -1) return;
      
      final bucketName = pathSegments[publicIndex + 1];
      final filePath = pathSegments.sublist(publicIndex + 2).join('/');
      
      if (bucketName.isEmpty || filePath.isEmpty) return;
      
      await _supabase.storage.from(bucketName).remove([filePath]);
      debugPrint('✅ Deleted status media from storage: $filePath');
    } catch (e) {
      debugPrint('❌ Failed to delete status media from storage: $e');
    }
  }

  Future<void> deleteStatus(String statusId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // ✅ Step 1: Get the status first to get the media URL
      final status = await _supabase
          .from('status_updates')
          .select('image_url')
          .eq('id', statusId)
          .eq('user_id', user.id)
          .single();

      final imageUrl = status['image_url'] as String?;

      // ✅ Step 2: Delete media file from storage if it exists
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await deleteFileFromStorage(imageUrl);
      }

      // ✅ Step 3: Delete the status record from the database
      final response = await _supabase
          .from('status_updates')
          .delete()
          .eq('id', statusId)
          .eq('user_id', user.id)
          .select();

      if (response.isEmpty) {
        throw Exception('Status not found or you do not have permission to delete it');
      }
    } catch (e) {
      debugPrint('Error deleting status: $e');
      rethrow;
    }
  }

  // ✅ Mark status as viewed (border changes, but status stays in list)
  Future<void> markStatusAsViewed(String statusId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.rpc('append_viewed_by', params: {
        'status_id': statusId,
        'user_id': user.id,
      });
    } catch (e) {
      debugPrint('Error marking status as viewed: $e');
    }
  }
}