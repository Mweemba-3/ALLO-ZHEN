import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/data/models/message_model.dart';
import 'package:allo_zhen/data/models/chat_conversation_model.dart';
import 'package:allo_zhen/data/models/call_model.dart'; // ✅ Import CallModel

class SqliteService {
  static final SqliteService _instance = SqliteService._internal();
  factory SqliteService() => _instance;
  SqliteService._internal();

  Database? _database;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'allo_zhen_local.db');
    return await openDatabase(
      path,
      version: 5, // ✅ Updated version (added call_logs)
      onCreate: (db, version) async {
        // --- Messages Table ---
        await db.execute('''
          CREATE TABLE local_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            content TEXT,
            content_type TEXT NOT NULL,
            media_url TEXT,
            is_read INTEGER DEFAULT 0,
            delivery_status TEXT DEFAULT 'sent',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_local_messages_peer 
          ON local_messages (sender_id, recipient_id)
        ''');

        // --- Call Logs Table (NEW) ---
        await db.execute('''
          CREATE TABLE local_call_logs (
            id TEXT PRIMARY KEY,
            caller_id TEXT NOT NULL,
            caller_name TEXT NOT NULL,
            caller_avatar TEXT,
            receiver_id TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            duration_seconds INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_local_call_logs_user 
          ON local_call_logs (caller_id, receiver_id)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS local_messages');
        await db.execute('''
          CREATE TABLE local_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            content TEXT,
            content_type TEXT NOT NULL,
            media_url TEXT,
            is_read INTEGER DEFAULT 0,
            delivery_status TEXT DEFAULT 'sent',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_local_messages_peer 
          ON local_messages (sender_id, recipient_id)
        ''');

        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE local_call_logs (
              id TEXT PRIMARY KEY,
              caller_id TEXT NOT NULL,
              caller_name TEXT NOT NULL,
              caller_avatar TEXT,
              receiver_id TEXT NOT NULL,
              type TEXT NOT NULL,
              status TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              duration_seconds INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_local_call_logs_user 
            ON local_call_logs (caller_id, receiver_id)
          ''');
        }
      },
    );
  }

  // ==================== MESSAGES ====================

  Future<void> insertMessage(MessageModel message) async {
    final db = await database;
    await db.insert('local_messages', {
      'id': message.id,
      'sender_id': message.senderId,
      'recipient_id': message.recipientId,
      'content': message.content,
      'content_type': message.type.name,
      'media_url': message.mediaUrl,
      'is_read': message.isRead ? 1 : 0,
      'delivery_status': 'delivered',
      'created_at': message.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MessageModel>> getMessagesForChat(String peerId) async {
    final db = await database;
    final myId = _currentUserId;
    if (myId == null) return [];

    final result = await db.query(
      'local_messages',
      where: '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [myId, peerId, peerId, myId],
      orderBy: 'created_at ASC',
    );

    return result.map((e) => MessageModel.fromMap({
      ...e,
      'is_read': e['is_read'] == 1,
    })).toList();
  }

  Future<List<ChatConversationModel>> getRecentConversations() async {
    final db = await database;
    final myId = _currentUserId;
    if (myId == null) return [];

    final peerIdResult = await db.rawQuery('''
      SELECT DISTINCT 
        CASE 
          WHEN sender_id = ? THEN recipient_id 
          ELSE sender_id 
        END as peer_id
      FROM local_messages
      WHERE sender_id = ? OR recipient_id = ?
    ''', [myId, myId, myId]);

    final List<String> peerIds = peerIdResult.map((row) => row['peer_id'] as String).toList();
    if (peerIds.isEmpty) return [];

    final List<ChatConversationModel> conversations = [];
    final Map<String, int> unreadMap = {};

    for (final peerId in peerIds) {
      final unreadResult = await db.rawQuery('''
        SELECT COUNT(*) as unread_count
        FROM local_messages
        WHERE recipient_id = ? AND is_read = 0
          AND (
            (sender_id = ? AND recipient_id = ?) OR
            (sender_id = ? AND recipient_id = ?)
          )
      ''', [myId, peerId, myId, myId, peerId]);

      final unreadCount = (unreadResult.first['unread_count'] as int?) ?? 0;
      unreadMap[peerId] = unreadCount;

      final latestResult = await db.rawQuery('''
        SELECT * FROM local_messages
        WHERE (sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)
        ORDER BY created_at DESC
        LIMIT 1
      ''', [myId, peerId, peerId, myId]);

      if (latestResult.isEmpty) continue;

      final row = latestResult.first;

      String previewText = row['content'] as String? ?? '';
      final String? mediaUrl = row['media_url'] as String?;
      final String? contentType = row['content_type'] as String?;

      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        if (contentType == 'image') previewText = '📷 Image';
        else if (contentType == 'audio') previewText = '🎵 Audio';
        else if (contentType == 'document') previewText = '📄 Document';
        else previewText = '📎 Attachment';
      }

      String peerName = 'User';
      String? avatarUrl;
      bool isOnline = false;

      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(peerId)) {
        try {
          final userResponse = await Supabase.instance.client
              .from('users')
              .select('id, public_display_name, avatar_url, is_online')
              .eq('id', peerId)
              .maybeSingle();

          if (userResponse != null) {
            peerName = userResponse['public_display_name'] as String? ?? 'User';
            avatarUrl = userResponse['avatar_url'] as String?;
            isOnline = userResponse['is_online'] as bool? ?? false;
          }
        } catch (_) {}
      }

      conversations.add(
        ChatConversationModel(
          peerId: peerId,
          peerName: peerName,
          avatarUrl: avatarUrl,
          lastMessage: previewText,
          lastMessageTime: DateTime.tryParse(row['created_at'] as String),
          unreadCount: unreadCount,
          isOnline: isOnline,
        ),
      );
    }

    return conversations;
  }

  Future<void> markAsRead(String messageId) async {
    final db = await database;
    await db.update(
      'local_messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete('local_messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> deleteChatMessages(String peerId) async {
    final db = await database;
    final myId = _currentUserId;
    if (myId == null) return;
    await db.delete(
      'local_messages',
      where: '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [myId, peerId, peerId, myId],
    );
  }

  // ==================== CALL LOGS (NEW) ====================

  /// Insert a call log into local SQLite
  Future<void> insertCallLog(CallModel call) async {
    final db = await database;
    await db.insert('local_call_logs', {
      'id': call.id,
      'caller_id': call.callerId,
      'caller_name': call.callerName,
      'caller_avatar': call.callerAvatar,
      'receiver_id': call.receiverId,
      'type': call.type.name,
      'status': call.status.name,
      'timestamp': call.timestamp.toIso8601String(),
      'duration_seconds': call.durationSeconds,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get all call logs for the current user (sorted newest first)
  Future<List<CallModel>> getCallLogs() async {
    final db = await database;
    final myId = _currentUserId;
    if (myId == null) return [];

    final result = await db.query(
      'local_call_logs',
      where: 'caller_id = ? OR receiver_id = ?',
      whereArgs: [myId, myId],
      orderBy: 'timestamp DESC',
    );

    return result.map((e) => CallModel.fromMap({
      ...e,
      'caller_avatar': e['caller_avatar'],
      'duration_seconds': e['duration_seconds'] ?? 0,
    })).toList();
  }

  /// Delete a single call log
  Future<void> deleteCallLog(String callId) async {
    final db = await database;
    await db.delete('local_call_logs', where: 'id = ?', whereArgs: [callId]);
  }

  /// Clear all call logs
  Future<void> clearCallLogs() async {
    final db = await database;
    await db.delete('local_call_logs');
  }
}