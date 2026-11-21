import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/gebco_service.dart';
import '../../../utils/nav_math.dart';
import '../view_models/map_viewmodel.dart';

/// Lembar hasil ketuk titik laut: koordinat + kedalaman GEBCO.
Future<void> showDepthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const DepthSheet(),
  );
}

class DepthSheet extends StatelessWidget {
  const DepthSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final point = vm.depthPoint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.water_drop, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Kedalaman',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Tutup',
                icon: const Icon(Icons.close),
                onPressed: () {
                  vm.clearDepth();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          if (point != null) ...[
            Text(
              '${NavMath.formatDecimal(point.latitude, fractionDigits: 5)}, '
              '${NavMath.formatDecimal(point.longitude, fractionDigits: 5)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Text(
              NavMath.formatLatLonDms(point.latitude, point.longitude),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (vm.depthLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (vm.depthError != null)
            _ErrorState(
              message: vm.depthError!,
              onRetry: point == null ? null : () => vm.lookupDepth(point),
            )
          else if (vm.depthResult != null)
            _DepthResultView(depth: vm.depthResult!),
          const SizedBox(height: 12),
          Text(
            'Sumber: GEBCO (grid ~450 m). Kedalaman laut/pantai saja — '
            'sungai tidak terukur.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DepthResultView extends StatelessWidget {
  const _DepthResultView({required this.depth});

  final DepthResult depth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final depthM = depth.depthM;
    if (depth.isLand) {
      return Row(
        children: [
          Icon(Icons.terrain, size: 36, color: scheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Titik ini di darat.',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.water, size: 36, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${depthM!.toStringAsFixed(1)} m',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'di bawah permukaan laut',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, color: scheme.error),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ],
    );
  }
}
