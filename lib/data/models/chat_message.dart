enum MessageType { text, image, audio }

class ChatMessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final MessageType type;
  final String? mediaUrl;
  final DateTime createdAt;
  final bool isRead;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.type = MessageType.text,
    this.mediaUrl,
    required this.createdAt,
    required this.isRead,
  });

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    MessageType parseType(String? typeStr) {
      switch (typeStr) {
        case 'image':
          return MessageType.image;
        case 'audio':
          return MessageType.audio;
        default:
          return MessageType.text;
      }
    }

    return ChatMessageModel(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      receiverId: map['receiver_id']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      type: parseType(map['type']?.toString()),
      mediaUrl: map['media_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      isRead: map['is_read'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'type': type.name,
      'media_url': mediaUrl,
      'is_read': isRead,
    };
  }
}