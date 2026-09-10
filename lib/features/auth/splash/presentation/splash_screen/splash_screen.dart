import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../presentation/widgets/brand_mark.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(),
            const SizedBox(height: 20),
            SvgPicture.asset(
              'assets/images/splash_screen_illustration.svg',
              width: 240,
              height: 180,
            ),
            const SizedBox(height: 20),
            const Text(
              '언어에 고픈 당신, 랭그리가 함께합니다.',
              style: TextStyle(color: Colors.black, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
