class ChatConversationModel {
  final String peerId;
  final String peerName;
  final String? avatarUrl;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  ChatConversationModel({
    required this.peerId,
    required this.peerName,
    this.avatarUrl,
    required this.lastMessage,
    this.lastMessageTime,
    required this.unreadCount,
    required this.isOnline,
  });

  factory ChatConversationModel.fromMap(Map<String, dynamic> map) {
    return ChatConversationModel(
      peerId: map['peer_id'] ?? '',
      peerName: map['peer_name'] ?? 'Unknown User',
      avatarUrl: map['avatar_url'],
      lastMessage: map['last_message'] ?? '',
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.tryParse(map['last_message_time'].toString())
          : null,
      unreadCount: map['unread_count'] ?? 0,
      isOnline: map['is_online'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'peer_id': peerId,
      'peer_name': peerName,
      'avatar_url': avatarUrl,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
      'is_online': isOnline,
    };
  }

  ChatConversationModel copyWith({
    String? peerId,
    String? peerName,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
  }) {
    return ChatConversationModel(
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}