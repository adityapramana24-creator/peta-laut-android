import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/waypoint.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/track_stats.dart';
import '../view_models/navigation_viewmodel.dart';

/// Detail jejak: statistik (jarak, durasi, kecepatan rata-rata)
/// + aksi tampilkan di peta / hapus.
Future<void> showTrackDetailSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TrackDetailSheet(track: track),
  );
}

class TrackDetailSheet extends StatefulWidget {
  const TrackDetailSheet({super.key, required this.track});

  final Track track;

  @override
  State<TrackDetailSheet> createState() => _TrackDetailSheetState();
}

class _TrackDetailSheetState extends State<TrackDetailSheet> {
  List<TrackPoint>? _points;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final full = await context
        .read<NavigationViewModel>()
        .loadTrack(widget.track.id);
    if (!mounted) return;
    setState(() {
      _points = full?.points ?? const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final points = _points ?? const <TrackPoint>[];
    final distanceM = TrackStats.totalDistanceM(points);
    final duration = TrackStats.duration(points);
    final avgKnots = TrackStats.averageSpeedKnots(points);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
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
            Text(
              widget.track.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Mulai ${NavMath.formatDateTime(widget.track.startedAt)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              _StatRow(
                icon: Icons.timeline,
                label: 'Jarak',
                value: NavMath.formatDistance(distanceM),
              ),
              _StatRow(
                icon: Icons.timer,
                label: 'Durasi',
                value: duration == null
                    ? '—'
                    : NavMath.formatDuration(duration),
              ),
              _StatRow(
                icon: Icons.speed,
                label: 'Kecepatan rata-rata',
                value: avgKnots == null
                    ? '—'
                    : '${avgKnots.toStringAsFixed(1)} knot',
              ),
              _StatRow(
                icon: Icons.place,
                label: 'Titik tercatat',
                value: '${points.length}',
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: points.isEmpty
                        ? null
                        : () {
                            nav.showTrackOnMap(
                              Track(
                                id: widget.track.id,
                                name: widget.track.name,
                                startedAt: widget.track.startedAt,
                                endedAt: widget.track.endedAt,
                                points: points,
                              ),
                            );
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.map),
                    label: const Text('Tampilkan di peta'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirmDelete(
                        context,
                        'Hapus jejak "${widget.track.name}"?',
                      );
                      if (ok && context.mounted) {
                        await nav.deleteTrack(widget.track.id);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    icon: Icon(Icons.delete, color: scheme.error),
                    label: Text(
                      'Hapus jejak',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hapus?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  return result ?? false;
}
