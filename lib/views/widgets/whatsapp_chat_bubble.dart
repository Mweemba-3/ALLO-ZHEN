import 'package:flutter/material.dart';

class WhatsAppThemeColors {
  static const Color lightHeader = Color(0xFF075E54);
  static const Color lightBackground = Color(0xFFECE5DD);
  static const Color lightPeerBubble = Colors.white;
  static const Color lightMyBubble = Color(0xFFDCF8C6);

  static const Color darkHeader = Color(0xFF121B22);
  static const Color darkBackground = Color(0xFF0B141A);
  static const Color darkPeerBubble = Color(0xFF202C33);
  static const Color darkMyBubble = Color(0xFF005C4B);
}

class WhatsAppChatBubble extends StatelessWidget {
  final Widget child;
  final bool isMe;
  final Color bubbleColor;

  const WhatsAppChatBubble({
    super.key,
    required this.child,
    required this.isMe,
    required this.bubbleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 40 : 8,
        right: isMe ? 8 : 40,
        top: 3,
        bottom: 3,
      ),
      child: CustomPaint(
        painter: _WhatsAppBubblePainter(
          color: bubbleColor,
          isMe: isMe,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: isMe ? 10 : 16,
            right: isMe ? 16 : 10,
            top: 7,
            bottom: 7,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WhatsAppBubblePainter extends CustomPainter {
  final Color color;
  final bool isMe;

  _WhatsAppBubblePainter({required this.color, required this.isMe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    final path = Path();
    const radius = 8.0;
    const tailWidth = 6.0;

    if (isMe) {
      path.moveTo(radius, 0);
      path.lineTo(size.width - tailWidth, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width - tailWidth, tailWidth);
      path.lineTo(size.width - tailWidth, size.height - radius);
      path.quadraticBezierTo(
        size.width - tailWidth,
        size.height,
        size.width - tailWidth - radius,
        size.height,
      );
      path.lineTo(radius, size.height);
      path.quadraticBezierTo(0, size.height, 0, size.height - radius);
      path.lineTo(0, radius);
      path.quadraticBezierTo(0, 0, radius, 0);
    } else {
      path.moveTo(tailWidth, tailWidth);
      path.lineTo(0, 0);
      path.lineTo(tailWidth, 0);
      path.lineTo(size.width - radius, 0);
      path.quadraticBezierTo(size.width, 0, size.width, radius);
      path.lineTo(size.width, size.height - radius);
      path.quadraticBezierTo(size.width, size.height, size.width - radius, size.height);
      path.lineTo(tailWidth + radius, size.height);
      path.quadraticBezierTo(tailWidth, size.height, tailWidth, size.height - radius);
      path.close();
    }

    canvas.drawPath(path.shift(const Offset(0, 0.8)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppBubblePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isMe != isMe;
  }
}