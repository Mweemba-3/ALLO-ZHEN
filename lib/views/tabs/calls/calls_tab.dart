import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/data/repositories/call_repository.dart';
import 'package:allo_zhen/data/models/call_model.dart';
import 'package:allo_zhen/core/database/sqlite_service.dart';
import 'call_screen.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  final CallRepository _callRepo = CallRepository();
  final SqliteService _sqlite = SqliteService();

  // ✅ Combined stream: local SQLite first, then Supabase
  Stream<List<CallModel>> _getCallLogsStream() {
    final currentUserId = _callRepo.currentUserId;
    if (currentUserId == null) return const Stream.empty();

    // 1. Get local call logs from SQLite
    final localStream = Stream.fromFuture(_sqlite.getCallLogs());

    // 2. Get remote call logs from Supabase
    final remoteStream = _callRepo.getCallHistoryStream();

    // 3. Merge them manually (no StreamGroup)
    return Stream.fromFutures([
      localStream.first,
      remoteStream.first,
    ]).asyncExpand((calls) {
      // Deduplicate by ID (keep latest)
      final Map<String, CallModel> uniqueCalls = {};
      for (final call in calls) {
        uniqueCalls[call.id] = call;
      }
      final result = uniqueCalls.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Stream.value(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Create Call Link Section ---
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Call link copied to clipboard!'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              title: const Text(
                'Create call link',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Share a link for your Allo Zhen call',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.05), height: 1),

            // --- Recent Calls Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Recent',
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // --- Call Logs Stream (Local + Remote) ---
            StreamBuilder<List<CallModel>>(
              stream: _getCallLogsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }

                final calls = snapshot.data ?? [];

                if (calls.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No recent call logs',
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: calls.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 80,
                    endIndent: 16,
                    color: Colors.white.withOpacity(0.03),
                  ),
                  itemBuilder: (context, index) {
                    final call = calls[index];
                    final bool isMissed = call.status == CallStatus.missed;
                    final bool isVideo = call.type == CallType.video;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              recipientId: call.callerId,
                              recipientName: call.callerName,
                              avatarUrl: call.callerAvatar,
                              isVideoCall: isVideo,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundColor: AppColors.surface,
                        backgroundImage: call.callerAvatar != null && call.callerAvatar!.isNotEmpty
                            ? NetworkImage(call.callerAvatar!)
                            : null,
                        child: call.callerAvatar == null || call.callerAvatar!.isEmpty
                            ? Text(
                                call.callerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        call.callerName,
                        style: TextStyle(
                          color: isMissed ? Colors.redAccent.shade100 : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              call.status == CallStatus.outgoing
                                  ? Icons.call_made_rounded
                                  : Icons.call_received_rounded,
                              size: 15,
                              color: isMissed ? Colors.redAccent : AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatTimestamp(call.timestamp),
                              style: TextStyle(
                                color: AppColors.textSecondary.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CallScreen(
                                recipientId: call.callerId,
                                recipientName: call.callerName,
                                avatarUrl: call.callerAvatar,
                                isVideoCall: isVideo,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'newCallBtn',
        backgroundColor: AppColors.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _showStartCallModal(context),
        child: const Icon(Icons.add_ic_call_rounded, color: Colors.white, size: 24),
      ),
    );
  }

  void _showStartCallModal(BuildContext context) {
    final SupabaseClient supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Select Contact to Call',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white10),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: supabase.from('users').select(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        );
                      }

                      final users = (snapshot.data ?? [])
                          .where((u) => u['id'] != currentUser?.id)
                          .toList();

                      if (users.isEmpty) {
                        return const Center(
                          child: Text(
                            'No contacts found',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final name = user['public_display_name'] ?? 'Allo User';
                          final avatar = user['avatar_url'];

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.background,
                              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                              child: avatar == null
                                  ? Text(
                                      name[0].toUpperCase(),
                                      style: const TextStyle(color: AppColors.primary),
                                    )
                                  : null,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(color: AppColors.textPrimary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.call_rounded, color: AppColors.primary),
                                  onPressed: () {
                                    Navigator.pop(modalContext);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CallScreen(
                                          recipientId: user['id'],
                                          recipientName: name,
                                          avatarUrl: avatar,
                                          isVideoCall: false,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.videocam_rounded, color: AppColors.primary),
                                  onPressed: () {
                                    Navigator.pop(modalContext);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CallScreen(
                                          recipientId: user['id'],
                                          recipientName: name,
                                          avatarUrl: avatar,
                                          isVideoCall: true,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}