class PhoneFormatter {
  static String sanitize(String countryCode, String phoneNumber) {
    final cleaned = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final code = countryCode.trim();
    return '$code$cleaned';
  }
}