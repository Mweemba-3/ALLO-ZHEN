class StatusModel {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? caption;
  final String? imageUrl;
  final String mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy;

  StatusModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.caption,
    this.imageUrl,
    required this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedBy,
  });

  factory StatusModel.fromMap(Map<String, dynamic> map) {
    return StatusModel(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      userName: map['user_name'] ?? 'Allo User',
      userAvatar: map['user_avatar'],
      caption: map['caption'],
      imageUrl: map['image_url'],
      mediaType: map['media_type'] ?? 'text',
      createdAt: DateTime.parse(map['created_at']),
      expiresAt: DateTime.parse(map['expires_at']),
      viewedBy: List<String>.from(map['viewed_by'] ?? []),
    );
  }
}