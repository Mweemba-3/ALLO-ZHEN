import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/data/models/message_model.dart';
import 'package:allo_zhen/data/models/chat_conversation_model.dart';
import 'package:allo_zhen/core/database/sqlite_service.dart';

class ChatRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SqliteService _sqlite = SqliteService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Stream<List<ChatConversationModel>> getRecentConversationsStream() {
    final myId = currentUserId;
    if (myId == null) return Stream.value([]);

    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((rawMessages) async {
          final Map<String, Map<String, dynamic>> latestMessagePerPeer = {};
          final Map<String, int> unreadCounts = {};

          for (final row in rawMessages) {
            final senderId = row['sender_id'] as String?;
            final recipientId = row['recipient_id'] as String?;

            // Skip if message doesn't involve current user
            if (senderId != myId && recipientId != myId) continue;

            // ❌ SKIP self-messages entirely (sender == me AND recipient == me)
            if (senderId == myId && recipientId == myId) continue;

            // Determine who the peer is
            final peerId = (senderId == myId) ? recipientId! : senderId!;

            // Only keep the latest message per peer
            if (!latestMessagePerPeer.containsKey(peerId)) {
              latestMessagePerPeer[peerId] = row;
            }

            // ✅ UNREAD COUNT: ONLY if I am the recipient AND sender is NOT me
            if (recipientId == myId && 
                senderId != myId && 
                (row['is_read'] == false)) {
              unreadCounts[peerId] = (unreadCounts[peerId] ?? 0) + 1;
            }
          }

          if (latestMessagePerPeer.isEmpty) return <ChatConversationModel>[];

          final peerIds = latestMessagePerPeer.keys.toList();

          final usersResponse = await _supabase
              .from('users')
              .select('id, public_display_name, avatar_url, is_online')
              .filter('id', 'in', peerIds);

          final Map<String, Map<String, dynamic>> usersMap = {
            for (var user in usersResponse) user['id'] as String: user
          };

          final List<ChatConversationModel> conversations = [];
          for (final peerId in peerIds) {
            final msgRow = latestMessagePerPeer[peerId]!;
            final user = usersMap[peerId];

            String previewText = msgRow['content'] ?? msgRow['body'] ?? '';
            final String? mediaUrl = msgRow['media_url'] as String?;
            final String? contentType = msgRow['content_type'] as String?;

            if (mediaUrl != null && mediaUrl.isNotEmpty) {
              if (contentType == 'image') previewText = '📷 Image';
              else if (contentType == 'audio') previewText = '🎵 Audio';
              else if (contentType == 'document') previewText = '📄 Document';
              else previewText = '📎 Attachment';
            }

            conversations.add(
              ChatConversationModel(
                peerId: peerId,
                peerName: user?['public_display_name'] ?? 'User',
                avatarUrl: user?['avatar_url'],
                lastMessage: previewText,
                lastMessageTime: DateTime.parse(msgRow['created_at']),
                unreadCount: unreadCounts[peerId] ?? 0,
                isOnline: user?['is_online'] ?? false,
              ),
            );
          }

          return conversations;
        });
  }

  Stream<List<MessageModel>> streamMessages({required String otherUserId}) {
    final myId = currentUserId;
    if (myId == null) return Stream.value([]);

    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((listOfMaps) {
          return listOfMaps
              .where((row) =>
                  (row['sender_id'] == myId && row['recipient_id'] == otherUserId) ||
                  (row['sender_id'] == otherUserId && row['recipient_id'] == myId))
              .map((row) => MessageModel.fromMap(row))
              .toList();
        });
  }

  Future<void> sendMessage({
    required String recipientId,
    required String content,
    required MessageType type,
    String? mediaUrl,
  }) async {
    final myId = currentUserId;
    if (myId == null) throw Exception("User is not authenticated");

    // ✅ Always mark your own messages as read for you
    await _supabase.from('messages').insert({
      'sender_id': myId,
      'recipient_id': recipientId,
      'content': content,
      'content_type': type.name,
      'media_url': mediaUrl,
      'is_read': true,          // ✅ Always true for sender
      'delivery_status': 'sent',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> markMessagesAsRead(String peerId) async {
    final myId = currentUserId;
    if (myId == null) return;

    // ✅ Mark unread messages from this peer as read
    await _supabase
        .from('messages')
        .update({'is_read': true})
        .eq('sender_id', peerId)
        .eq('recipient_id', myId)
        .eq('is_read', false);
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
      print('✅ Deleted file from storage: $filePath');
    } catch (e) {
      print('❌ Failed to delete file from storage: $e');
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    final myId = currentUserId;
    if (myId == null) return false;

    try {
      final message = await _supabase
          .from('messages')
          .select('media_url')
          .eq('id', messageId)
          .single();

      final mediaUrl = message['media_url'] as String?;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        await deleteFileFromStorage(mediaUrl);
      }

      await _supabase.from('messages').delete().eq('id', messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<Map<String, dynamic>?> streamUserPresence(String userId) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => data.isNotEmpty ? data.first : null);
  }

  RealtimeChannel subscribeToTypingStatus(
    String peerId, {
    required Function(bool isTyping) onTypingChanged,
  }) {
    final ids = [currentUserId ?? '', peerId]..sort();
    final channelName = 'chat_typing_${ids.join('_')}';
    final channel = _supabase.channel(channelName);
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (payload['user_id'] != currentUserId) {
          onTypingChanged(payload['is_typing'] == true);
        }
      },
    ).subscribe();
    return channel;
  }

  Future<void> sendTypingNotification(RealtimeChannel channel, bool isTyping) async {
    await channel.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': currentUserId, 'is_typing': isTyping},
    );
  }

  Future<String?> uploadAttachment(File file, String bucketName) async {
    try {
      final myId = currentUserId;
      if (myId == null) return null;
      final fileExt = file.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$myId.$fileExt';
      final filePath = '$myId/$fileName';
      await _supabase.storage.from(bucketName).upload(
        filePath,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );
      return _supabase.storage.from(bucketName).getPublicUrl(filePath);
    } catch (_) {
      return null;
    }
  }
}