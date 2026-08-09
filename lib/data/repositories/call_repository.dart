import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/call_model.dart';
import '../../core/database/sqlite_service.dart';

class CallRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SqliteService _sqlite = SqliteService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Stream<List<CallModel>> getCallHistoryStream() {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return const Stream.empty();

    return _supabase
        .from('call_logs')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .map((data) => data.map((json) => CallModel.fromMap(json)).toList());
  }

  Future<void> logCall({
    required String callerId,
    required String callerName,
    required String receiverId,
    required CallType type,
    required CallStatus status,
    int durationSeconds = 0,
  }) async {
    try {
      final call = CallModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        callerId: callerId,
        callerName: callerName,
        receiverId: receiverId,
        type: type,
        status: status,
        timestamp: DateTime.now(),
        durationSeconds: durationSeconds,
      );

      await _supabase.from('call_logs').insert(call.toMap());
      await _sqlite.insertCallLog(call);
    } catch (e) {
      debugPrint('Error logging call: $e');
    }
  }

  // --- SIGNALING (Fixed) ---

  Future<void> sendCallNotification({
  required String callerId,
  required String callerName,
  required String recipientId,
  required bool isVideo,
  required String callId, // ✅ Added
}) async {
  final channel = _supabase.realtime.channel('incoming_calls');
  await channel.subscribe();
  await channel.sendBroadcastMessage(
    event: 'incoming_call',
    payload: {
      'caller_id': callerId,
      'caller_name': callerName,
      'recipient_id': recipientId,
      'is_video': isVideo,
      'call_id': callId, // ✅ Pass callId
    },
  );
}

  /// Listen for incoming call notifications
  Stream<Map<String, dynamic>> listenForIncomingCalls() {
    final myId = currentUserId;
    if (myId == null) return const Stream.empty();

    final controller = StreamController<Map<String, dynamic>>();
    
    final channel = _supabase
        .realtime
        .channel('incoming_calls')
        .onBroadcast(
          event: 'incoming_call',
          callback: (payload) {
            controller.add(payload);
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }

  /// Send a signaling message (offer, answer, candidate)
  Future<void> sendSignalingMessage(Map<String, dynamic> message) async {
    final recipientId = message['recipient_id'] as String?;
    final callId = message['call_id'] as String?;
    if (recipientId == null || callId == null) return;

    final channel = _supabase.realtime.channel('call_$callId');
    await channel.subscribe();
    await channel.sendBroadcastMessage(
      event: 'signal',
      payload: message,
    );
  }

  /// Listen for signaling messages for a specific call
  Stream<Map<String, dynamic>> listenForSignaling(String callId) {
    final controller = StreamController<Map<String, dynamic>>();
    
    final channel = _supabase
        .realtime
        .channel('call_$callId')
        .onBroadcast(
          event: 'signal',
          callback: (payload) {
            controller.add(payload);
          },
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
    };

    return controller.stream;
  }
}