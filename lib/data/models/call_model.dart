enum CallType { audio, video }
enum CallStatus { incoming, outgoing, missed }

class CallModel {
  final String id;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String receiverId;
  final CallType type;
  final CallStatus status;
  final DateTime timestamp;
  final int durationSeconds;

  CallModel({
    required this.id,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.receiverId,
    required this.type,
    required this.status,
    required this.timestamp,
    this.durationSeconds = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'caller_id': callerId,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'receiver_id': receiverId,
      'type': type.name,
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      id: map['id'] ?? '',
      callerId: map['caller_id'] ?? '',
      callerName: map['caller_name'] ?? 'Allo User',
      callerAvatar: map['caller_avatar'],
      receiverId: map['receiver_id'] ?? '',
      type: map['type'] == 'video' ? CallType.video : CallType.audio,
      status: CallStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => CallStatus.missed,
      ),
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      durationSeconds: map['duration_seconds'] ?? 0,
    );
  }
}