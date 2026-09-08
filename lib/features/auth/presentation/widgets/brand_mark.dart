import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 42.0 : 68.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.navy,
            borderRadius: BorderRadius.circular(size * .32),
          ),
          child: Icon(
            Icons.chat_bubble_rounded,
            color: AppTheme.mint,
            size: size * .55,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          const Text(
            'LANGGRY',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ],
    );
  }
}
