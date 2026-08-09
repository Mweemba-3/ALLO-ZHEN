import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _presenceChannel;

  // ✅ BUCKET NAME: 'avatars' (strictly matched to your actual bucket)
  static const String _avatarBucket = 'avatars';

  /// Sanitizes phone numbers to standard format (+260...)
  String _cleanPhoneNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('+')) {
      return '+${trimmed.replaceAll(RegExp(r'\D'), '')}';
    }
    return '+${trimmed.replaceAll(RegExp(r'\D'), '')}';
  }

  /// Checks if a user is currently authenticated
  User? get currentUser => _supabase.auth.currentUser;

  /// Checks if a phone number exists in public.users
  Future<bool> isPhoneNumberRegistered(String phoneNumber) async {
    try {
      final cleanPhone = _cleanPhoneNumber(phoneNumber);
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('phone_number', cleanPhone)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking phone registration: $e');
      return false;
    }
  }

  /// Authenticates an existing user with Phone and Secret Name
  Future<User> signInUser({
    required String phoneNumber,
    required String secretLoginName,
  }) async {
    final cleanPhone = _cleanPhoneNumber(phoneNumber);
    final emailFormatted = '$cleanPhone@allo.local';

    try {
      final AuthResponse res = await _supabase.auth.signInWithPassword(
        email: emailFormatted,
        password: secretLoginName,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthException('Invalid login credentials.');
      }

      await setOnlineStatus(true);
      return user;
    } on AuthException catch (e) {
      debugPrint('AuthException in signInUser: ${e.message}');
      throw AuthException(
        e.message.contains('Invalid login credentials')
            ? 'Incorrect phone number or secret screen name.'
            : e.message,
      );
    } catch (e) {
      debugPrint('General error in signInUser: $e');
      rethrow;
    }
  }

  /// ✅ Hard-deletes an avatar file from storage (if it exists)
  Future<void> _deleteAvatarFromStorage(String? avatarUrl) async {
    if (avatarUrl == null || avatarUrl.isEmpty) return;

    try {
      // Extract the file path from the full URL
      final uri = Uri.parse(avatarUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_avatarBucket);
      if (bucketIndex == -1) return;

      // Reconstruct the storage path (e.g., 'avatars/user123.jpg')
      final storagePath = pathSegments.sublist(bucketIndex).join('/');

      await _supabase.storage.from(_avatarBucket).remove([storagePath]);
      debugPrint('✅ Deleted old avatar: $storagePath');
    } catch (e) {
      // Silently fail – don't block the upload if deletion fails
      debugPrint('⚠️ Could not delete old avatar: $e');
    }
  }

  /// Registers a brand new user account
  Future<void> registerUser({
    required String phoneNumber,
    required String secretLoginName,
    required String publicDisplayName,
    required String statusQuote,
    File? avatarFile,
  }) async {
    final cleanPhone = _cleanPhoneNumber(phoneNumber);

    final bool phoneExists = await isPhoneNumberRegistered(cleanPhone);
    if (phoneExists) {
      throw const AuthException(
        'This phone number is already registered. Please sign in.',
      );
    }

    if (_supabase.auth.currentUser != null) {
      await _supabase.auth.signOut();
    }

    final emailFormatted = '$cleanPhone@allo.local';
    User? currentUser;

    try {
      final AuthResponse res = await _supabase.auth.signUp(
        email: emailFormatted,
        password: secretLoginName,
      );
      currentUser = res.user;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('already registered') ||
          e.statusCode == '400') {
        try {
          final AuthResponse res = await _supabase.auth.signInWithPassword(
            email: emailFormatted,
            password: secretLoginName,
          );
          currentUser = res.user;
        } catch (_) {
          throw const AuthException(
            'This phone number is already registered. Please sign in.',
          );
        }
      } else {
        rethrow;
      }
    }

    if (currentUser == null) {
      throw const AuthException('Could not create user account.');
    }

    String? publicAvatarUrl;
    if (avatarFile != null) {
      try {
        final rawBytes = await avatarFile.readAsBytes();
        final img.Image? decodedImage = img.decodeImage(rawBytes);

        List<int> uploadBytes = rawBytes;
        if (decodedImage != null) {
          final img.Image resizedImage = img.copyResize(
            decodedImage,
            width: 400,
            height: 400,
            maintainAspect: true,
          );
          uploadBytes = img.encodeJpg(resizedImage, quality: 70);
        }

        final String filePath = '${currentUser.id}.jpg';

        // ✅ Upload new avatar (no old one exists yet)
        await _supabase.storage.from(_avatarBucket).uploadBinary(
              filePath,
              Uint8List.fromList(uploadBytes),
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );

        publicAvatarUrl = _supabase.storage.from(_avatarBucket).getPublicUrl(filePath);
      } catch (e) {
        debugPrint('⚠️ Avatar upload failed during registration: $e');
        // Continue without avatar
      }
    }

    final nowIso = DateTime.now().toIso8601String();

    await _supabase.from('users').upsert({
      'id': currentUser.id,
      'phone_number': cleanPhone,
      'secret_login_name': secretLoginName,
      'public_display_name': publicDisplayName,
      'status_quote': statusQuote,
      'avatar_url': publicAvatarUrl,
      'phone_privacy_enabled': false,
      'is_online': true,
      'is_official': false,
      'last_seen': nowIso,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    await setOnlineStatus(true);
  }

  /// ✅ Updates the user's avatar (deletes old, uploads new)
  Future<String?> updateUserAvatar(File avatarFile) async {
    final user = currentUser;
    if (user == null) throw const AuthException('User not authenticated.');

    try {
      // 1. Fetch current user data to get the old avatar URL
      final currentData = await _supabase
          .from('users')
          .select('avatar_url')
          .eq('id', user.id)
          .single();

      final String? oldAvatarUrl = currentData['avatar_url'];

      // 2. Hard-delete the old avatar from storage
      await _deleteAvatarFromStorage(oldAvatarUrl);

      // 3. Process and upload the new image
      final rawBytes = await avatarFile.readAsBytes();
      final img.Image? decodedImage = img.decodeImage(rawBytes);

      List<int> uploadBytes = rawBytes;
      if (decodedImage != null) {
        final img.Image resizedImage = img.copyResize(
          decodedImage,
          width: 400,
          height: 400,
          maintainAspect: true,
        );
        uploadBytes = img.encodeJpg(resizedImage, quality: 70);
      }

      final String filePath = '${user.id}.jpg';

      await _supabase.storage.from(_avatarBucket).uploadBinary(
            filePath,
            Uint8List.fromList(uploadBytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final String newAvatarUrl = _supabase.storage.from(_avatarBucket).getPublicUrl(filePath);

      // 4. Update the database
      await _supabase.from('users').update({
        'avatar_url': newAvatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      return newAvatarUrl;
    } catch (e) {
      debugPrint('Failed to update avatar: $e');
      return null;
    }
  }

  /// ✅ Removes the user's avatar (hard-deletes from storage + sets to null)
  Future<bool> removeUserAvatar() async {
    final user = currentUser;
    if (user == null) return false;

    try {
      // 1. Fetch current avatar URL
      final currentData = await _supabase
          .from('users')
          .select('avatar_url')
          .eq('id', user.id)
          .single();

      final String? oldAvatarUrl = currentData['avatar_url'];

      // 2. Hard-delete from storage
      await _deleteAvatarFromStorage(oldAvatarUrl);

      // 3. Set to null in database
      await _supabase.from('users').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      return true;
    } catch (e) {
      debugPrint('Failed to remove avatar: $e');
      return false;
    }
  }

  /// Updates user presence status (online / last_seen)
  Future<void> setOnlineStatus(bool isOnline) async {
    final user = currentUser;
    if (user == null) return;

    final nowIso = DateTime.now().toIso8601String();
    try {
      await _supabase.from('users').update({
        'is_online': isOnline,
        'last_seen': nowIso,
      }).eq('id', user.id);
    } catch (e) {
      debugPrint('Failed to update online status: $e');
    }
  }

  /// Binds Supabase Realtime Presence channel for active tracking
  void initPresenceTracking() {
    final user = currentUser;
    if (user == null) return;

    _presenceChannel = _supabase.channel('online_users');

    _presenceChannel!
        .onPresenceSync((payload) {
          debugPrint('Presence Sync Payload: $payload');
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _presenceChannel!.track({
              'user_id': user.id,
              'online_at': DateTime.now().toIso8601String(),
            });
            await setOnlineStatus(true);
          }
        });
  }

  /// ✅ Hard-deletes the user's entire account, including avatar
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) throw const AuthException('User not authenticated.');

    try {
      // 1. Delete avatar from storage
      final currentData = await _supabase
          .from('users')
          .select('avatar_url')
          .eq('id', user.id)
          .single();
      await _deleteAvatarFromStorage(currentData['avatar_url']);

      // 2. Delete user from auth (cascades to public.users)
      await _supabase.auth.admin.deleteUser(user.id);

      // 3. Sign out locally
      await signOut();
    } catch (e) {
      debugPrint('Failed to delete account: $e');
      rethrow;
    }
  }

  /// Signs out and sets last_seen
  Future<void> signOut() async {
    await setOnlineStatus(false);
    if (_presenceChannel != null) {
      await _supabase.removeChannel(_presenceChannel!);
    }
    await _supabase.auth.signOut();
  }
}