import 'package:url_launcher/url_launcher.dart';

class EmailLauncher {
  static Future<void> triggerDisputeEmail(String phoneNumber) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'mscodeforge369@gmail.com',
      queryParameters: {
        'subject': '[Number Registration Issue] $phoneNumber',
        'body': 'Hello MS CodeForge Support,\n\nI am disputing the registration state of the phone number: $phoneNumber.\n\nPlease review my ownership claim.\n\nRegards,',
      },
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }
}