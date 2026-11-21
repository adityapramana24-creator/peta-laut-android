import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/waypoint.dart';
import '../../../utils/nav_math.dart';
import '../view_models/navigation_viewmodel.dart';

/// Lembar pembangun rute: ketuk waypoint berurutan, beri nama,
/// atur kecepatan, lalu simpan. Ringkasan jarak + ETA live.
Future<void> showRouteBuilderSheet(
  BuildContext context, {
  List<String>? initialSelectedIds,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RouteBuilderSheet(
      initialSelectedIds: initialSelectedIds,
    ),
  );
}

class RouteBuilderSheet extends StatefulWidget {
  const RouteBuilderSheet({super.key, this.initialSelectedIds});

  final List<String>? initialSelectedIds;

  @override
  State<RouteBuilderSheet> createState() => _RouteBuilderSheetState();
}

class _RouteBuilderSheetState extends State<RouteBuilderSheet> {
  final _nameController = TextEditingController();
  late List<String> _selected;
  double _speedKnots = 8;

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.initialSelectedIds ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final waypoints = nav.waypoints;
    final selectedPoints = <(double, double)>[];
    for (final id in _selected) {
      for (final wp in waypoints) {
        if (wp.id == id) selectedPoints.add((wp.latitude, wp.longitude));
      }
    }
    final totalM = RouteMath.totalDistanceM(selectedPoints);
    final eta = RouteMath.totalEta(selectedPoints, _speedKnots);
    final canSave =
        _selected.length >= 2 && _nameController.text.trim().isNotEmpty;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Buat rute baru',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ketuk titik berurutan — angka menunjukkan urutan rute.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama rute',
                hintText: 'mis. Banjarmasin – Surabaya',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Kecepatan: ${_speedKnots.toStringAsFixed(0)} knot',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: Slider(
                    value: _speedKnots,
                    min: 2,
                    max: 20,
                    divisions: 18,
                    label: '${_speedKnots.toStringAsFixed(0)} knot',
                    onChanged: (v) => setState(() => _speedKnots = v),
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: waypoints.length,
                itemBuilder: (context, index) {
                  final wp = waypoints[index];
                  final order = _selected.indexOf(wp.id);
                  final selected = order >= 0;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Text(
                        selected ? '${order + 1}' : '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                    title: Text(wp.name),
                    subtitle: Text(
                      '${NavMath.formatDecimal(wp.latitude)}, '
                      '${NavMath.formatDecimal(wp.longitude)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle)
                        : const Icon(Icons.circle_outlined),
                    onTap: () => _toggle(wp.id),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selected.length < 2
                        ? 'Pilih minimal 2 titik.'
                        : '${_selected.length} titik · '
                            '${selectedPoints.length - 1} kaki · '
                            '${NavMath.formatDistance(totalM)} · '
                            'ETA ${NavMath.formatEta(eta)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Hapus pilihan'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSave
                    ? () async {
                        final route = RoutePlan(
                          id: 'rt_${DateTime.now().microsecondsSinceEpoch}',
                          name: _nameController.text.trim(),
                          waypointIds: List.of(_selected),
                          speedKnots: _speedKnots,
                          createdAt: DateTime.now(),
                        );
                        await nav.saveRoute(route);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    : null,
                icon: const Icon(Icons.save),
                label: const Text('Simpan rute'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
