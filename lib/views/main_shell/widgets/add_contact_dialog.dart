import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../chat_detail_screen.dart';

class AddContactDialog extends StatefulWidget {
  const AddContactDialog({super.key});

  @override
  State<AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<AddContactDialog> {
  final TextEditingController _queryController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isSearching = false;
  Map<String, dynamic>? _foundUser;
  String? _errorMessage;

  Future<void> _verifyUser() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _foundUser = null;
    });

    try {
      // Query PostgreSQL for Public Name or Phone Number match
      final response = await _supabase
          .from('users')
          .select()
          .or('phone_number.eq.$query,public_display_name.ilike.%$query%')
          .maybeSingle();

      if (response != null) {
        setState(() => _foundUser = response);
      } else {
        setState(() => _errorMessage = 'User not registered on Allo Zhen.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Verification error. Check input format.');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.primary.withOpacity(0.2), width: 1),
      ),
      title: const Row(
        children: [
          Icon(Icons.person_search_rounded, color: AppColors.primary, size: 26),
          SizedBox(width: 12),
          Text(
            'Find on Allo Zhen',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _queryController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter Phone (+260...) or Public Name',
              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 13),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          if (_isSearching)
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)
          else if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.redAccent.shade100, fontSize: 13, fontWeight: FontWeight.w500),
            )
          else if (_foundUser != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    child: Text(
                      (_foundUser!['public_display_name'] ?? 'A')[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAlignment.start,
                      children: [
                        Text(
                          _foundUser!['public_display_name'] ?? 'User',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          _foundUser!['phone_privacy_enabled'] == true
                              ? 'Phone Hidden'
                              : (_foundUser!['phone_number'] ?? ''),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (_foundUser == null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _verifyUser,
            child: const Text('Verify User', style: TextStyle(color: Colors.white)),
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatDetailScreen(
                    recipientId: _foundUser!['id'],
                    recipientDisplayName: _foundUser!['public_display_name'] ?? 'Allo User',
                  ),
                ),
              );
            },
            child: const Text('Start Chat', style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}