import 'dart:async';
import 'package:flutter/material.dart';
import 'package:allo_zhen/data/models/chat_conversation_model.dart';
import 'package:allo_zhen/data/repositories/chat_repository.dart';
import 'package:allo_zhen/views/tabs/chats/chat_detail_screen.dart';
import 'package:allo_zhen/views/tabs/chats/new_chat_screen.dart';
import 'package:allo_zhen/core/services/notification_service.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final ChatRepository _chatRepo = ChatRepository();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final ValueNotifier<List<ChatConversationModel>> _conversationsNotifier =
      ValueNotifier<List<ChatConversationModel>>([]);

  final ValueNotifier<int> _totalUnreadNotifier = ValueNotifier<int>(0);

  Map<String, int> _lastUnreadCounts = {};
  StreamSubscription? _conversationSubscription;

  @override
  void initState() {
    super.initState();
    _listenToConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _conversationSubscription?.cancel();
    _conversationsNotifier.dispose();
    _totalUnreadNotifier.dispose();
    super.dispose();
  }

  void _listenToConversations() {
  _conversationSubscription = _chatRepo
      .getRecentConversationsStream()
      .listen((conversations) {
    if (!mounted) return;

    for (final chat in conversations) {
      final previous = _lastUnreadCounts[chat.peerId] ?? 0;
      final current = chat.unreadCount;

      // ✅ ONLY show notification if peer is NOT current user
      if (current > previous && 
          chat.peerId != _chatRepo.currentUserId && 
          chat.lastMessageTime != null) {
        _showLocalNotification(chat);
      }

      _lastUnreadCounts[chat.peerId] = current;
    }

    _conversationsNotifier.value = conversations;

    // ✅ Update total unread count - EXCLUDE self
    final totalUnread = conversations.fold<int>(0, (sum, chat) {
      if (chat.peerId != _chatRepo.currentUserId) {
        return sum + chat.unreadCount;
      }
      return sum;
    });
    _totalUnreadNotifier.value = totalUnread;
  });
}

  void _showLocalNotification(ChatConversationModel chat) {
    final String title = chat.peerName;
    final String body = chat.lastMessage.isNotEmpty ? chat.lastMessage : 'New message';

    NotificationService.instance.showNotification(
      id: chat.peerId.hashCode,
      title: title,
      body: body,
    );
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _openNewChatScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewChatScreen(),
      ),
    );
  }

  ValueNotifier<int> get totalUnreadNotifier => _totalUnreadNotifier;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 12,
        title: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 0.8,
            ),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase().trim();
              });
            },
            style: TextStyle(
              fontSize: 14.5,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Search chats...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.grey.shade500,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<List<ChatConversationModel>>(
        valueListenable: _conversationsNotifier,
        builder: (context, rawConversations, child) {
          final conversations = rawConversations.where((chat) {
            final nameMatch = chat.peerName.toLowerCase().contains(_searchQuery);
            final msgMatch = chat.lastMessage.toLowerCase().contains(_searchQuery);
            return nameMatch || msgMatch;
          }).toList();

          if (conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No chats found matching "$_searchQuery"'
                      : 'No conversations yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontSize: 15,
                  ),
                ),
              ),
            );
          }

          // ✅ SORT NEWEST AT THE BOTTOM
          final sortedConversations = List.from(conversations)
            ..sort((a, b) => b.lastMessageTime!.compareTo(a.lastMessageTime!));

          return ListView.builder(
            itemCount: sortedConversations.length,
            itemBuilder: (context, index) {
              final item = sortedConversations[index];
              final initials = item.peerName.isNotEmpty
                  ? item.peerName[0].toUpperCase()
                  : '?';
              final hasUnread = item.unreadCount > 0;

              return RepaintBoundary(
                child: InkWell(
                  onTap: () async {
                    // ✅ Cancel notification for this chat when opened
                    await NotificationService.instance.cancelNotification(item.peerId.hashCode);
                    
                    await _chatRepo.markMessagesAsRead(item.peerId);
                    _lastUnreadCounts[item.peerId] = 0;

                    final updated = _conversationsNotifier.value.map((c) {
                      if (c.peerId == item.peerId) {
                        return c.copyWith(unreadCount: 0);
                      }
                      return c;
                    }).toList() as List<ChatConversationModel>;

                    _conversationsNotifier.value = updated;

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatDetailScreen(
                            recipientId: item.peerId,
                            recipientDisplayName: item.peerName,
                            recipientAvatar: item.avatarUrl,
                          ),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isDark
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade300,
                              backgroundImage:
                                  (item.avatarUrl != null && item.avatarUrl!.isNotEmpty)
                                      ? NetworkImage(item.avatarUrl!)
                                      : null,
                              child: (item.avatarUrl == null || item.avatarUrl!.isEmpty)
                                  ? Text(
                                      initials,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black54,
                                      ),
                                    )
                                  : null,
                            ),
                            if (item.isOnline)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.peerName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: hasUnread
                                      ? (isDark ? Colors.white : Colors.black87)
                                      : (isDark ? Colors.white54 : Colors.grey.shade600),
                                  fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimestamp(item.lastMessageTime),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: hasUnread
                                    ? Theme.of(context).primaryColor
                                    : (isDark ? Colors.white38 : Colors.grey.shade500),
                                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (hasUnread)
                              Container(
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${item.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewChatScreen,
        elevation: 3,
        child: const Icon(Icons.message),
      ),
    );
  }
}