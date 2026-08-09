import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/data/repositories/auth_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthRepository _authRepo = AuthRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _displayName;
  String? _statusQuote;
  String? _avatarUrl;
  bool _phonePrivacyEnabled = false;
  bool _isDarkMode = false;
  bool _isLoading = false;

  late final TextEditingController _nameController;
  late final TextEditingController _statusController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _statusController = TextEditingController();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final response = await _supabase
        .from('users')
        .select('public_display_name, status_quote, avatar_url, phone_privacy_enabled')
        .eq('id', userId)
        .single();

    setState(() {
      _displayName = response['public_display_name'] ?? 'User';
      _statusQuote = response['status_quote'] ?? 'Hey there! I am using Allo Zhen.';
      _avatarUrl = response['avatar_url'];
      _phonePrivacyEnabled = response['phone_privacy_enabled'] ?? false;
      
      _nameController.text = _displayName ?? '';
      _statusController.text = _statusQuote ?? '';
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final file = File(image.path);
    setState(() => _isLoading = true);

    final newUrl = await _authRepo.updateUserAvatar(file);

    setState(() {
      _avatarUrl = newUrl;
      _isLoading = false;
    });

    if (newUrl == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update avatar')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated successfully')),
      );
    }
  }

  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Profile Picture'),
        content: const Text('Are you sure you want to remove your profile picture?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final success = await _authRepo.removeUserAvatar();
      setState(() {
        _avatarUrl = success ? null : _avatarUrl;
        _isLoading = false;
      });

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase.from('users').update({
      'public_display_name': _displayName,
      'status_quote': _statusQuote,
      'phone_privacy_enabled': _phonePrivacyEnabled,
    }).eq('id', userId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  Future<void> _logout() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm) {
      await _authRepo.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/phone_input',
          (route) => false,
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account, profile picture, and all data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm) {
      try {
        await _authRepo.deleteAccount();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/auth', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete account. Please try again.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _isDarkMode ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _isDarkMode ? const Color(0xFF121B22) : const Color(0xFF075E54),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Modern Profile Header Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    onLongPress: _avatarUrl != null ? _removeAvatar : null,
                    child: Stack(
                      children: [
                        Hero(
                          tag: 'user_avatar',
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: _isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
                            backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                ? NetworkImage(_avatarUrl!)
                                : null,
                            child: _avatarUrl == null || _avatarUrl!.isEmpty
                                ? Text(
                                    _displayName?.isNotEmpty == true
                                        ? _displayName![0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: _isDarkMode ? Colors.white70 : Colors.grey.shade700,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (_isLoading)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A884),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
                                width: 3,
                              ),
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _displayName ?? 'Loading...',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusQuote ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isDarkMode ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Settings Section Group
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('PROFILE INFORMATION'),
                  Container(
                    decoration: BoxDecoration(
                      color: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildTextFieldTile(
                          'Display Name',
                          _nameController,
                          (val) => _displayName = val,
                          icon: Icons.person_outline,
                        ),
                        Divider(height: 1, color: _isDarkMode ? Colors.white10 : Colors.grey.shade100),
                        _buildTextFieldTile(
                          'Status Quote',
                          _statusController,
                          (val) => _statusQuote = val,
                          maxLines: 2,
                          icon: Icons.info_outline,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  _buildSectionHeader('PRIVACY PREFERENCES'),
                  Container(
                    decoration: BoxDecoration(
                      color: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildSwitchTile(
                      'Hide Phone Number',
                      'Other users won\'t see your phone number in chats',
                      _phonePrivacyEnabled,
                      (val) => setState(() => _phonePrivacyEnabled = val),
                    ),
                  ),

                  const SizedBox(height: 20),
                  _buildSectionHeader('ACTIONS & ACCOUNT'),
                  Container(
                    decoration: BoxDecoration(
                      color: _isDarkMode ? const Color(0xFF1F2C34) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildActionTile('Save Changes', Icons.save_rounded, _updateProfile, color: const Color(0xFF00A884)),
                        _buildDivider(),
                        _buildActionTile('Remove Profile Picture', Icons.account_circle_outlined, _removeAvatar, color: Colors.amber.shade700),
                        _buildDivider(),
                        _buildActionTile('Logout', Icons.logout_rounded, _logout, color: Colors.orangeAccent),
                        _buildDivider(),
                        _buildActionTile('Delete Account', Icons.delete_outline_rounded, _deleteAccount, color: Colors.redAccent),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _isDarkMode ? Colors.white54 : Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1, 
      thickness: 1, 
      indent: 56, 
      color: _isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
    );
  }

  Widget _buildTextFieldTile(
    String label,
    TextEditingController controller,
    Function(String) onChanged, {
    int maxLines = 1,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: maxLines,
        style: TextStyle(
          color: _isDarkMode ? Colors.white : Colors.black87,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: _isDarkMode ? Colors.white60 : Colors.grey.shade600,
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, color: _isDarkMode ? Colors.white54 : Colors.grey.shade500, size: 22),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF00A884),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: TextStyle(
          color: _isDarkMode ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: _isDarkMode ? Colors.white54 : Colors.grey.shade600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildActionTile(String label, IconData icon, VoidCallback onTap, {Color? color}) {
    final activeColor = color ?? (_isDarkMode ? Colors.white70 : Colors.black87);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: activeColor, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: activeColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _isDarkMode ? Colors.white24 : Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}