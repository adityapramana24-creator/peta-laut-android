import 'package:flutter/material.dart';

import '../../../config/app_constants.dart';

/// Banner keselamatan permanen di atas peta (R-22):
/// "Alat bantu saja. Bukan pengganti navigasi resmi kapal."
class SafetyBanner extends StatelessWidget {
  const SafetyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer.withValues(alpha: 0.92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              AppConstants.safetyWarning,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onErrorContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
