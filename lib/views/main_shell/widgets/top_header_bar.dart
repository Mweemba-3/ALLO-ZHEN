import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';

class TopHeaderBar extends StatefulWidget implements PreferredSizeWidget {
  final Function(String)? onMenuSelected;

  const TopHeaderBar({
    super.key,
    this.onMenuSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  State<TopHeaderBar> createState() => _TopHeaderBarState();
}

class _TopHeaderBarState extends State<TopHeaderBar> {
  String? _userName;
  String? _userAvatarUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null) {
        final response = await Supabase.instance.client
            .from('users')
            .select('public_display_name, avatar_url')
            .eq('id', currentUserId)
            .single();

        if (mounted) {
          setState(() {
            _userName = response['public_display_name'] as String?;
            _userAvatarUrl = response['avatar_url'] as String?;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching header user data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.06),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              // --- Logged-in User Profile Photo & Name ---
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    backgroundImage: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                        ? NetworkImage(_userAvatarUrl!)
                        : null,
                    child: _userAvatarUrl == null || _userAvatarUrl!.isEmpty
                        ? Text(
                            (_userName != null && _userName!.isNotEmpty)
                                ? _userName![0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      _userName ?? 'Allo Zhen',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // --- Custom Dark Popup Menu ---
              PopupMenuButton<String>(
                onSelected: widget.onMenuSelected,
                elevation: 12,
                color: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: AppColors.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                offset: const Offset(0, 48),
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ),
                itemBuilder: (BuildContext context) => [
                  _buildMenuItem(
                    value: 'new_group',
                    icon: Icons.group_add_outlined,
                    label: 'New Group',
                  ),
                  _buildMenuItem(
                    value: 'broadcast',
                    icon: Icons.campaign_outlined,
                    label: 'New Broadcast',
                  ),
                  _buildMenuItem(
                    value: 'starred',
                    icon: Icons.star_border_rounded,
                    label: 'Starred Messages',
                  ),
                  const PopupMenuDivider(height: 1),
                  _buildMenuItem(
                    value: 'settings',
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}