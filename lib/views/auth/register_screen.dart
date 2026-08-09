import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers matching your Allo app user profile fields
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _secretNameController = TextEditingController();
  final _displayNameController = TextEditingController();

  File? _selectedImageFile; // Set this via ImagePicker (Gallery/Camera)
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _secretNameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // Helper method to display detailed error pop-ups on screen
  void _showErrorDialog(String title, String details) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: SingleChildScrollView(
          child: SelectableText(details), // Allows copying error text
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _registerUser() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('--- STARTING REGISTRATION PROCESS ---');

      // 1. Sign up user in Supabase Auth
      final String emailFormatted = _phoneController.text.trim().contains('@')
          ? _phoneController.text.trim()
          : '${_phoneController.text.trim()}@allo.local';

      debugPrint('1. Calling Auth SignUp for: $emailFormatted');

      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: emailFormatted,
        password: _passwordController.text.trim(),
      );

      final user = res.user;
      if (user == null) {
        throw Exception('Auth signup returned null. Check Supabase Auth settings.');
      }

      debugPrint('2. Auth Success! User ID: ${user.id}');

      // 2. Upload Profile Picture directly to Supabase Storage Bucket
      String? publicAvatarUrl;

      if (_selectedImageFile != null) {
        debugPrint('3. Processing image upload to avatars bucket...');
        
        // Compress image before uploading
        final rawBytes = await _selectedImageFile!.readAsBytes();
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

        // File path inside the bucket: e.g. avatars/USER_ID.jpg
        final String filePath = '${user.id}.jpg';

        // Upload file directly to the 'avatars' storage bucket
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
              filePath,
              Uint8List.fromList(uploadBytes),
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true, // Overwrite if re-registering/updating
              ),
            );

        // Get the clean public web URL
        publicAvatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(filePath);

        debugPrint('Avatar uploaded successfully! Public URL: $publicAvatarUrl');
      } else {
        debugPrint('3. No image selected. Proceeding without avatar.');
      }

      // 3. Upsert User Profile into public.users with the image URL
      debugPrint('4. Upserting profile into public.users table...');
      final nowIso = DateTime.now().toIso8601String();

      await Supabase.instance.client.from('users').upsert({
        'id': user.id,
        'phone_number': _phoneController.text.trim(),
        'secret_login_name': _secretNameController.text.trim(),
        'public_display_name': _displayNameController.text.trim(),
        'status_quote': 'Hey there! I am using Allo.',
        'avatar_url': publicAvatarUrl, // Store clean HTTP URL (e.g. https://.../avatars/USER_ID.jpg)
        'phone_privacy_enabled': false,
        'is_online': true,
        'is_official': false,
        'last_seen': nowIso,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      debugPrint('5. REGISTRATION FULLY SUCCESSFUL & LOGGED IN!');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account registered and logged in successfully!')),
      );

      // TODO: Navigate to your home/dashboard screen here, e.g.:
      // Navigator.pushReplacementNamed(context, '/home');

    } on StorageException catch (e, stackTrace) {
      final errorLog = 'StorageException [${e.statusCode}]: ${e.message}\n\nStackTrace:\n$stackTrace';
      debugPrint('=== STORAGE ERROR ===\n$errorLog');
      _showErrorDialog('Storage Error (${e.statusCode})', errorLog);

    } on PostgrestException catch (e, stackTrace) {
      final errorLog = 'PostgrestException [Code: ${e.code}]: ${e.message}\nDetails: ${e.details}\nHint: ${e.hint}\n\nStackTrace:\n$stackTrace';
      debugPrint('=== DATABASE ERROR ===\n$errorLog');
      _showErrorDialog('Database SQL Error', errorLog);

    } on AuthException catch (e, stackTrace) {
      final errorLog = 'AuthException [${e.statusCode}]: ${e.message}\n\nStackTrace:\n$stackTrace';
      debugPrint('=== AUTH ERROR ===\n$errorLog');
      _showErrorDialog('Auth Error', errorLog);

    } catch (e, stackTrace) {
      final errorLog = 'Unexpected Error: $e\n\nStackTrace:\n$stackTrace';
      debugPrint('=== GENERAL ERROR ===\n$errorLog');
      _showErrorDialog('General Registration Error', errorLog);

    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Phone Number Input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '+260978494159',
              ),
            ),
            const SizedBox(height: 12),

            // Password Input
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 12),

            // Secret Login Name
            TextField(
              controller: _secretNameController,
              decoration: const InputDecoration(labelText: 'Secret Login Name'),
            ),
            const SizedBox(height: 12),

            // Display Name
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(labelText: 'Public Display Name'),
            ),
            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoading ? null : _registerUser,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }
}