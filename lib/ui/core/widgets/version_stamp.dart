import 'package:flutter/material.dart';

import '../../../config/app_constants.dart';

/// Stempel versi terlihat di UI (R-38): "v1.2 · 21 Nov 2026".
class VersionStamp extends StatelessWidget {
  const VersionStamp({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onDark ? Colors.white70 : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? Colors.black45 : scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        AppConstants.versionLabel,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}
