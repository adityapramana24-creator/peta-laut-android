import 'package:flutter/material.dart';

import '../../config/app_constants.dart';
import '../core/widgets/version_stamp.dart';

/// Layar splash: logo kapten + nama app + kredit + stempel versi.
/// Ditampilkan ~900 ms saat app mulai (lihat PetaLautApp).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.splashBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/peta-laut-logo.webp',
                width: 180,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'PETA LAUT',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppConstants.credit,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                color: AppConstants.goldAccent,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 24),
            const VersionStamp(onDark: true),
          ],
        ),
      ),
    );
  }
}
