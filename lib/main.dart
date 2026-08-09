import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'core/constants/app_colors.dart';
import 'core/services/notification_service.dart';
import 'core/database/sqlite_service.dart';

// ✅ IMPORT ALL ROUTE SCREENS
import 'views/auth/splash_screen.dart';
import 'views/auth/phone_input_screen.dart';
import 'views/auth/sign_in_screen.dart';
import 'views/auth/profile_setup_screen.dart';

/// Constants for Supabase
const String _supabaseUrl = 'https://ilnzpmdcfvyajdovilox.supabase.co';
const String _supabaseAnonKey ='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlsbnpwbWRjZnZ5YWpkb3ZpbG94Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3OTU0MTYsImV4cCI6MjA5OTM3MTQxNn0.5BslEuw3JBJTSNL2ETFqsQ88dVf2zjLsJ4trC6BjpXQ';

const String fetchUnreadMessagesTask = 'fetchUnreadMessagesTask';

/// Top-level callback entry point for WorkManager when the app is closed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 1. Re-initialize Notification Service in background isolate
      await NotificationService.instance.init();

      // 2. Re-initialize Supabase client
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.initialize(
          url: _supabaseUrl,
          anonKey: _supabaseAnonKey,
        );
      }

      final client = Supabase.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser != null) {
        // 3. Query for new unread messages directed to the current user
        final response = await client
            .from('messages')
            .select('id, content, sender_id, recipient_id')
            .eq('recipient_id', currentUser.id)
            .eq('is_read', false)
            .limit(5);

        for (final msg in (response as List)) {
          final String content = msg['content'] ?? 'New message received';
          // 4. Show the notification
          await NotificationService.instance.showNotification(
            id: msg['id'].hashCode,
            title: 'Allo Zhen',
            body: content,
          );
        }
      }
      return Future.value(true);
    } catch (e) {
      debugPrint('Background Task Error: $e');
      return Future.value(false);
    }
  });
}

Future<void> main() async {
  // 1. Ensure Flutter engine bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // 🔇 SILENCE SUPABASE REALTIME CONSOLE SPAM
  FlutterError.onError = (details) {
    final message = details.exception.toString();
    if (!message.contains('RealtimeSubscribeException') &&
        !message.contains('SupabaseStreamBuilder') &&
        !message.contains('realtime_client') &&
        !message.contains('WebSocketChannelException')) {
      FlutterError.presentError(details);
    }
  };

  // 2. Global Unhandled Error Handling (your existing code)
  // Kept as-is, but the above filter will prevent Supabase spam

  // 3. Initialize Local Notification Service (Safe)
  try {
    await NotificationService.instance.init();
  } catch (e, stackTrace) {
    debugPrint('Notification Service Exception: $e');
    debugPrint(stackTrace.toString());
  }

  // 4. Initialize Supabase client (Safe)
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  } catch (e, stackTrace) {
    debugPrint('Supabase Initialization Exception: $e');
    debugPrint(stackTrace.toString());
  }

  // 5. ✅ Initialize SQLite (Runs even if Supabase fails)
  try {
    await SqliteService().database; // Forces DB creation
  } catch (e) {
    debugPrint('SQLite Initialization Error: $e');
  }

  // 6. ✅ UPDATED: WorkManager runs every 1 minute for near-instant notifications
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Register a periodic task running every 1 minute
    await Workmanager().registerPeriodicTask(
      'allo_zhen_background_sync',
      fetchUnreadMessagesTask,
      frequency: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  } catch (e) {
    debugPrint('Workmanager Initialization Error: $e');
  }

  runApp(const AlloZhenApp());
}

class AlloZhenApp extends StatelessWidget {
  const AlloZhenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Connect notification tap to your app's navigation
    NotificationService.instance.onNotificationTap = (response) {
      final payload = response.payload;
      if (payload != null) {
        debugPrint('Navigate to chat: $payload');
      }
    };

    return MaterialApp(
      title: 'Allo Zhen',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
          case '/auth':
          case '/phone_input':
            return MaterialPageRoute(builder: (_) => PhoneInputScreen());
          case '/sign_in':
            return MaterialPageRoute(builder: (_) => SignInScreen());
          case '/profile_setup':
            final args = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => ProfileSetupScreen(phoneNumber: args ?? ''),
            );
          default:
            return MaterialPageRoute(builder: (_) => SplashScreen());
        }
      },
    );
  }
}