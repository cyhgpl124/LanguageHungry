import 'package:flutter/material.dart';

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    required this.isAi,
    this.imageUrl,
    this.radius = 24,
    super.key,
  });

  final bool isAi;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final fallback = Icon(
      isAi ? Icons.smart_toy_rounded : Icons.person_rounded,
      size: radius,
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: isAi ? Colors.teal.shade100 : Colors.indigo.shade100,
      foregroundColor: isAi ? Colors.teal : Colors.indigo,
      child: url == null || url.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            ),
    );
  }
}
