import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/database/sqlite_service.dart'; // ✅ SQLite import
import '../main_shell/main_shell_screen.dart';
import 'phone_input_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _handleAuthRouting();
  }

  Future<void> _handleAuthRouting() async {
    // Artificial startup delay per Blueprint v8.0 Section 2.1
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session != null) {
        // ✅ OFFLINE-FIRST: Check SQLite for local session validity
        final sqlite = SqliteService();
        final hasMessages = await sqlite.getMessagesForChat(session.user.id);
        
        if (hasMessages.isNotEmpty || session.user.id != null) {
          // Valid local session → Go to Main Shell (even if offline)
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const MainShellScreen(),
            ),
          );
          return;
        }

        // ✅ ONLINE FALLBACK: Validate with Supabase if local data is empty
        final userRecord = await supabase
            .from('users')
            .select('id')
            .eq('id', session.user.id)
            .maybeSingle();

        if (!mounted) return;

        if (userRecord != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const MainShellScreen(),
            ),
          );
        } else {
          // User was deleted from database! Wipe stale local session
          await supabase.auth.signOut();
          if (!mounted) return;
          
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PhoneInputScreen()),
          );
        }
      } else {
        // Unauthenticated → Phone Input / Registration
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PhoneInputScreen()),
        );
      }
    } catch (e) {
      debugPrint('Splash routing error: $e');
      if (mounted) {
        // Safe fallback: sign out and go to phone input
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PhoneInputScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Allo Zhen',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}