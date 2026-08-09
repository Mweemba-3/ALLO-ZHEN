import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:allo_zhen/core/constants/app_colors.dart';
import 'package:allo_zhen/views/tabs/chats/chat_detail_screen.dart';

class SystemUser {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String phoneNumber;

  SystemUser({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    required this.phoneNumber,
  });

  factory SystemUser.fromMap(Map<String, dynamic> map) {
    return SystemUser(
      id: map['id']?.toString() ?? '',
      fullName: map['public_display_name']?.toString() ??
          map['full_name']?.toString() ??
          map['name']?.toString() ??
          map['username']?.toString() ??
          'Allo Zhen User',
      avatarUrl: map['avatar_url']?.toString() ?? map['avatar']?.toString(),
      phoneNumber: map['phone_number']?.toString() ??
          map['phone']?.toString() ??
          '',
    );
  }
}

class ContactDisplayItem {
  final String name;
  final String rawPhone;
  final String normalizedPhone;
  final bool isOnAlloZhen;
  final SystemUser? systemUser;

  ContactDisplayItem({
    required this.name,
    required this.rawPhone,
    required this.normalizedPhone,
    required this.isOnAlloZhen,
    this.systemUser,
  });
}

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<ContactDisplayItem> _allContacts = [];
  List<ContactDisplayItem> _filteredContacts = [];

  @override
  void initState() {
    super.initState();
    _loadAndVerifyContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _cleanDigits(String phone) {
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  String _getLast9Digits(String phone) {
    final digits = _cleanDigits(phone);
    if (digits.length >= 9) {
      return digits.substring(digits.length - 9);
    }
    return digits;
  }

  String _toLocalFormat(String phone) {
    String digits = _cleanDigits(phone);

    if (digits.startsWith('260') && digits.length >= 12) {
      digits = '0${digits.substring(3)}';
    } else if (digits.length == 9) {
      digits = '0$digits';
    } else if (digits.length > 10) {
      digits = '0${digits.substring(digits.length - 9)}';
    }

    return digits;
  }

  void _navigateToChat(SystemUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          recipientId: user.id,
          recipientDisplayName: user.fullName,
          recipientAvatar: user.avatarUrl,
        ),
      ),
    );
  }

  Future<void> _loadAndVerifyContacts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    List<SystemUser> registeredUsers = [];

    try {
      final List<dynamic> response = await _supabase.from('users').select();
      registeredUsers = response.map((item) => SystemUser.fromMap(item)).toList();
    } catch (e) {
      debugPrint('Error fetching users from Supabase: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Database sync issue: $e');
      }
    }

    final Map<String, SystemUser> registeredMap = {};
    for (var user in registeredUsers) {
      final rawClean = _cleanDigits(user.phoneNumber);
      final local = _toLocalFormat(user.phoneNumber);
      final suffix = _getLast9Digits(user.phoneNumber);

      if (rawClean.isNotEmpty) registeredMap[rawClean] = user;
      if (local.isNotEmpty) registeredMap[local] = user;
      if (suffix.isNotEmpty) registeredMap[suffix] = user;
    }

    List<ContactDisplayItem> verifiedContacts = [];

    try {
      bool permissionGranted = await FlutterContacts.requestPermission(readonly: true);

      if (permissionGranted) {
        final deviceContacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        for (var contact in deviceContacts) {
          final displayName = contact.displayName.isNotEmpty
              ? contact.displayName
              : 'Unknown Contact';

          for (var phoneObj in contact.phones) {
            final raw = phoneObj.number;
            final clean = _cleanDigits(raw);
            final local = _toLocalFormat(raw);
            final suffix = _getLast9Digits(raw);

            if (clean.isEmpty) continue;

            final SystemUser? matchedUser = registeredMap[clean] ??
                registeredMap[local] ??
                registeredMap[suffix];

            if (matchedUser != null) {
              verifiedContacts.add(
                ContactDisplayItem(
                  name: displayName,
                  rawPhone: raw,
                  normalizedPhone: local.isNotEmpty ? local : raw,
                  isOnAlloZhen: true,
                  systemUser: matchedUser,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Device contacts access denied. Please grant permissions in settings.';
          });
        }
      }
    } catch (e) {
      debugPrint('Error reading device contacts: $e');
    }

    // ✅ REMOVED: The loop that added ALL registered users

    verifiedContacts.sort((a, b) {
      if (a.isOnAlloZhen && !b.isOnAlloZhen) return -1;
      if (!a.isOnAlloZhen && b.isOnAlloZhen) return 1;
      return a.name.compareTo(b.name);
    });

    if (mounted) {
      setState(() {
        _allContacts = verifiedContacts;
        _filteredContacts = verifiedContacts;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredContacts = _allContacts);
      return;
    }

    setState(() {
      _filteredContacts = _allContacts.where((c) {
        return c.name.toLowerCase().contains(query) ||
            c.rawPhone.contains(query) ||
            c.normalizedPhone.contains(query);
      }).toList();
    });
  }

  Future<void> _sendSmsInvite(String phone) async {
    final Uri smsLaunchUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: <String, String>{
        'body': 'Hey! Join me on Allo Zhen so we can chat. Download the app!',
      },
    );
    if (await canLaunchUrl(smsLaunchUri)) {
      await launchUrl(smsLaunchUri);
    }
  }

  void _showAddUserDialog() {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  bool isSubmitting = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (bottomSheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> verifyAndAddUser() async {
            final name = nameController.text.trim();
            final rawPhoneInput = phoneController.text.trim();

            if (name.isEmpty || rawPhoneInput.isEmpty) {
              ScaffoldMessenger.of(bottomSheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Please enter both name and phone number.'),
                  backgroundColor: Colors.orangeAccent,
                ),
              );
              return;
            }

            setModalState(() => isSubmitting = true);

            try {
              // ✅ Clean the input phone number
              final cleanedInput = _cleanDigits(rawPhoneInput);
              final localFormat = _toLocalFormat(rawPhoneInput);
              final last9 = _getLast9Digits(rawPhoneInput);

              // ✅ Try multiple matching strategies
              final List<dynamic> existing = await _supabase
                  .from('users')
                  .select()
                  .or(
                    'phone_number.eq.$cleanedInput,' +
                    'phone_number.eq.$localFormat,' +
                    'phone_number.ilike.%$last9%'
                  );

              setModalState(() => isSubmitting = false);

              if (existing.isNotEmpty) {
                final registeredUser = SystemUser.fromMap(
                  existing.first as Map<String, dynamic>,
                );

                if (mounted) {
                  Navigator.pop(bottomSheetContext);
                  _loadAndVerifyContacts();
                  _navigateToChat(registeredUser);
                }
              } else {
                if (mounted) {
                  Navigator.pop(bottomSheetContext);

                  showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: const Text(
                        'Not on Allo Zhen',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      content: Text(
                        '$name ($rawPhoneInput) is not registered on Allo Zhen yet.\n\nWould you like to send them an SMS invite?',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _sendSmsInvite(rawPhoneInput);
                          },
                          child: const Text('Send Invite',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                }
              }
            } catch (e) {
              debugPrint('Verification error: $e');
              setModalState(() => isSubmitting = false);
              if (mounted) {
                ScaffoldMessenger.of(bottomSheetContext).showSnackBar(
                  SnackBar(
                    content: Text('Verification failed: ${e.toString()}'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              top: 24,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Contact to Allo Zhen',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Phone Number (e.g. 097xxxxxxx)',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : verifyAndAddUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Verify & Start Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Select Contact',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: AppColors.primary),
            onPressed: _showAddUserDialog,
          )
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.redAccent.withOpacity(0.15),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _filteredContacts.isEmpty
                    ? const Center(
                        child: Text(
                          'No contacts found on Allo Zhen.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredContacts.length,
                        itemBuilder: (context, index) {
                          final item = _filteredContacts[index];

                          return ListTile(
                            onTap: item.isOnAlloZhen && item.systemUser != null
                                ? () => _navigateToChat(item.systemUser!)
                                : () => _sendSmsInvite(item.rawPhone),
                            leading: CircleAvatar(
                              backgroundColor: item.isOnAlloZhen
                                  ? AppColors.primary
                                  : Colors.grey.shade700,
                              backgroundImage: item.systemUser?.avatarUrl != null &&
                                      item.systemUser!.avatarUrl!.isNotEmpty
                                  ? NetworkImage(item.systemUser!.avatarUrl!)
                                  : null,
                              child: item.systemUser?.avatarUrl == null ||
                                      item.systemUser!.avatarUrl!.isEmpty
                                  ? Text(
                                      item.name.isNotEmpty
                                          ? item.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(color: Colors.white),
                                    )
                                  : null,
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              item.normalizedPhone.isNotEmpty
                                  ? item.normalizedPhone
                                  : item.rawPhone,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            trailing: item.isOnAlloZhen
                                ? ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (item.systemUser != null) {
                                        _navigateToChat(item.systemUser!);
                                      }
                                    },
                                    child: const Text(
                                      'Chat',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  )
                                : OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.grey.shade600),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => _sendSmsInvite(item.rawPhone),
                                    child: const Text(
                                      'Invite',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}