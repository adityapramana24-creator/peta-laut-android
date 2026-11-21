import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dial kompas di sudut peta: berputar mengikuti rotasi peta
/// sehingga huruf "U" selalu menunjuk utara sejati di layar.
/// Ketuk untuk beralih utara-ke-atas / heading-up.
class CompassDial extends StatelessWidget {
  const CompassDial({
    super.key,
    required this.mapRotation,
    required this.headingUp,
    required this.onTap,
  });

  /// Rotasi peta saat ini (derajat, searah jarum jam).
  final double mapRotation;
  final bool headingUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: scheme.surface,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Jarum utara berputar mengikuti +rotasi peta (F-R1):
              // saat peta berputar θ searah jarum jam, arah utara
              // di layar berada pada bearing +θ dari atas layar.
              Transform.rotate(
                angle: mapRotation * math.pi / 180,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.navigation,
                      size: 18,
                      color: headingUp
                          ? scheme.primary
                          : scheme.error,
                    ),
                    Text(
                      'U',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 3,
                child: Text(
                  headingUp ? 'HDG' : 'UTR',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
