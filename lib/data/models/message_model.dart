import 'package:allo_zhen/data/models/chat_message.dart';

enum MessageType { text, image, audio, document }

class MessageModel {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final MessageType type;
  final String? mediaUrl;
  final DateTime createdAt;
  final bool isRead;
  final String deliveryStatus;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    this.type = MessageType.text,
    this.mediaUrl,
    required this.createdAt,
    required this.isRead,
    this.deliveryStatus = 'sent',
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    MessageType parseType(String? typeStr) {
      switch (typeStr) {
        case 'image':
          return MessageType.image;
        case 'audio':
          return MessageType.audio;
        case 'document':
          return MessageType.document; // ✅ Fixed
        default:
          return MessageType.text;
      }
    }

    return MessageModel(
      id: map['id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      recipientId: map['recipient_id']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      type: parseType(map['content_type']?.toString()),
      mediaUrl: map['media_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      isRead: map['is_read'] ?? false,
      deliveryStatus: map['delivery_status'] ?? 'sent',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sender_id': senderId,
      'recipient_id': recipientId,
      'content': content,
      'content_type': type.name,
      'media_url': mediaUrl,
      'is_read': isRead,
      'delivery_status': deliveryStatus,
    };
  }
}