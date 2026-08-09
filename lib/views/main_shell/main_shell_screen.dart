import 'dart:async';
import 'package:flutter/material.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/views/settings/settings_screen.dart';
import 'package:allo_zhen/data/repositories/call_repository.dart';
import 'package:allo_zhen/views/tabs/calls/call_screen.dart';
import '../tabs/chats/chats_tab.dart';
import '../tabs/status/status_tab.dart';
import '../tabs/calls/calls_tab.dart';
import 'widgets/top_header_bar.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  final CallRepository _callRepo = CallRepository();
  StreamSubscription? _incomingCallSubscription;
  StreamSubscription? _signalingSubscription;

  final List<Widget> _tabs = const [
    ChatsTab(),
    StatusTab(),
    CallsTab(),
  ];

  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    // 1. Listen for the call notification (popup)
    _incomingCallSubscription = _callRepo.listenForIncomingCalls().listen((payload) {
      if (!mounted) return;
      
      final callerId = payload['caller_id'] as String;
      final callerName = payload['caller_name'] as String;
      final isVideo = payload['is_video'] as bool? ?? false;
      final callId = payload['call_id'] as String; // ✅ Get callId

      // Show the incoming call dialog
      _showIncomingCallDialog(callerId, callerName, isVideo, callId);
    });

    // 2. Listen for the actual signaling (SDP offers, answers, candidates)
    //    We need a callId to listen, so we'll wait until a call is started
    //    This is now handled inside CallScreen
  }

  void _showIncomingCallDialog(String callerId, String callerName, bool isVideo, String callId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Incoming Call', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary,
                child: Text(
                  callerName[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              const SizedBox(height: 12),
              Text(callerName, style: const TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                isVideo ? 'Video call' : 'Audio call',
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
          actions: [
            // ❌ Decline
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Optional: send decline signal
              },
              child: const Text('Decline', style: TextStyle(color: Colors.redAccent)),
            ),
            // ✅ Answer
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      recipientId: callerId,
                      recipientName: callerName,
                      isVideoCall: isVideo,
                      isIncoming: true,
                      callId: callId, // ✅ Pass callId
                    ),
                  ),
                );
              },
              child: const Text('Answer', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _incomingCallSubscription?.cancel();
    _signalingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64.0),
        child: TopHeaderBar(
          onMenuSelected: (value) {
            switch (value) {
              case 'new_group': break;
              case 'broadcast': break;
              case 'starred': break;
              case 'settings':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
                break;
            }
          },
        ),
      ),
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1.0)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary.withOpacity(0.5),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.donut_large_outlined),
              activeIcon: Icon(Icons.donut_large_rounded),
              label: 'Status',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.call_outlined),
              activeIcon: Icon(Icons.call_rounded),
              label: 'Calls',
            ),
          ],
        ),
      ),
    );
  }
}