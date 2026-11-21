import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_constants.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/models/waypoint.dart';
import '../../../utils/nav_math.dart';
import '../view_models/navigation_viewmodel.dart';
import 'manual_waypoint_dialog.dart';

/// Lembar pembangun rute: ketik waypoint baru atau ketuk titik yang
/// sudah ada, urutkan dengan seret, atur kecepatan, lalu simpan.
/// Rute langsung tergambar di peta begitu disimpan (ronde 2).
/// [existingRoute] diisi saat mengubah rute yang sudah ada.
Future<void> showRouteBuilderSheet(
  BuildContext context, {
  List<String>? initialSelectedIds,
  RoutePlan? existingRoute,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RouteBuilderSheet(
      initialSelectedIds:
          initialSelectedIds ?? existingRoute?.waypointIds,
      existingRoute: existingRoute,
    ),
  );
}

/// Dialog ketik kecepatan jelajah (knot, 1–50). Dipakai pembangun
/// rute dan detail rute. Mengembalikan nilai baru, atau null bila
/// dibatalkan.
Future<double?> showSpeedEditDialog(
  BuildContext context, {
  required double initialKnots,
}) {
  final controller = TextEditingController(
    text: initialKnots.toStringAsFixed(0),
  );
  String? error;
  return showDialog<double>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final raw = controller.text.trim().replaceAll(',', '.');
            final value = double.tryParse(raw);
            if (value == null || value < 1 || value > 50) {
              setState(() {
                error = 'Isi angka 1–50 knot.';
              });
              return;
            }
            Navigator.of(context).pop(value);
          }

          return AlertDialog(
            title: const Text('Kecepatan jelajah'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Kecepatan (knot)',
                hintText: 'mis. 8',
                errorText: error,
                suffixText: 'knot',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      );
    },
  ).then((value) {
    controller.dispose();
    return value;
  });
}

class RouteBuilderSheet extends StatefulWidget {
  const RouteBuilderSheet({
    super.key,
    this.initialSelectedIds,
    this.existingRoute,
  });

  final List<String>? initialSelectedIds;
  final RoutePlan? existingRoute;

  @override
  State<RouteBuilderSheet> createState() => _RouteBuilderSheetState();
}

class _RouteBuilderSheetState extends State<RouteBuilderSheet> {
  late final TextEditingController _nameController;
  late List<String> _selected;
  double _speedKnots = AppConstants.defaultSpeedKnots;
  bool _speedInitialized = false;
  bool _speedFromSog = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingRoute?.name ?? '',
    );
    _selected = List.of(widget.initialSelectedIds ?? const []);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_speedInitialized) return;
    _speedInitialized = true;
    final existing = widget.existingRoute;
    if (existing != null) {
      // Mengubah rute: pakai kecepatan yang sudah tersimpan di rute.
      _speedKnots = existing.speedKnots.clamp(1.0, 50.0).toDouble();
      return;
    }
    final nav = context.read<NavigationViewModel>();
    final sog = nav.sogKnots;
    if (sog != null && sog > 0.5) {
      // Default dari SOG GPS saat ini (kapal sedang bergerak).
      _speedKnots = sog.clamp(1.0, 50.0).toDouble();
      _speedFromSog = true;
    } else {
      // Else kecepatan jelajah terakhir yang disimpan user.
      _speedKnots = context.read<SettingsService>().cruiseSpeedKnots;
    }
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

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final id = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, id);
    });
  }

  /// Tambah waypoint dengan koordinat ketik, lalu langsung masuk
  /// ke daftar rute ini.
  Future<void> _addTypedWaypoint() async {
    final result = await showManualWaypointDialog(context);
    if (result == null || !mounted) return;
    final saved = await context.read<NavigationViewModel>().addWaypoint(
          name: result.name,
          latitude: result.latitude,
          longitude: result.longitude,
        );
    if (saved == null || !mounted) return;
    setState(() {
      if (!_selected.contains(saved.id)) _selected.add(saved.id);
    });
  }

  Future<void> _editWaypoint(Waypoint wp) async {
    final result =
        await showManualWaypointDialog(context, existing: wp);
    if (result == null || !mounted) return;
    await context.read<NavigationViewModel>().updateWaypoint(
          id: wp.id,
          name: result.name,
          latitude: result.latitude,
          longitude: result.longitude,
        );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final byId = {for (final w in nav.waypoints) w.id: w};
    final selectedWps = _selected
        .map((id) => byId[id])
        .whereType<Waypoint>()
        .toList();
    final points =
        selectedWps.map((w) => (w.latitude, w.longitude)).toList();
    final legs = RouteMath.legs(points);
    final totalM = RouteMath.totalDistanceM(points);
    final eta = RouteMath.totalEta(points, _speedKnots);
    final unselected = nav.waypoints
        .where((w) => !_selected.contains(w.id))
        .toList();
    final isEditing = widget.existingRoute != null;
    final canSave =
        selectedWps.length >= 2 && _nameController.text.trim().isNotEmpty;

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
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isEditing ? 'Ubah rute' : 'Buat rute baru',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ketik waypoint baru atau ketuk titik di bawah — angka '
              'menunjukkan urutan rute. Seret gagang untuk mengubah '
              'urutan.',
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
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final v = await showSpeedEditDialog(
                        context,
                        initialKnots: _speedKnots,
                      );
                      if (v != null) setState(() => _speedKnots = v);
                    },
                    child: Text(
                      'Kecepatan: ${_speedKnots.toStringAsFixed(0)} knot '
                      '(ketuk angka untuk mengetik)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _speedKnots,
              min: 1,
              max: 50,
              divisions: 49,
              label: '${_speedKnots.toStringAsFixed(0)} knot',
              onChanged: (v) => setState(() => _speedKnots = v),
            ),
            if (_speedFromSog)
              Text(
                'Kecepatan awal dari SOG GPS saat ini.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addTypedWaypoint,
                icon: const Icon(Icons.keyboard),
                label: const Text('+ Tambah waypoint ketik'),
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Titik dalam rute (${selectedWps.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (selectedWps.isEmpty)
                      Text(
                        nav.waypoints.isEmpty
                            ? 'Belum ada titik sama sekali — ketik '
                                'waypoint baru dengan tombol di atas.'
                            : 'Belum ada titik dalam rute — ketuk '
                                'titik di bawah untuk menambah.',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: selectedWps.length,
                        onReorder: _reorder,
                        itemBuilder: (context, index) {
                          final wp = selectedWps[index];
                          final leg =
                              index == 0 ? null : legs[index - 1];
                          return _SelectedRow(
                            key: ValueKey(wp.id),
                            waypoint: wp,
                            number: index + 1,
                            legFromPrevious: leg,
                            onEdit: () => _editWaypoint(wp),
                            onRemove: () => _toggle(wp.id),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Titik lain — ketuk untuk menambah ke rute',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (unselected.isEmpty)
                      Text(
                        nav.waypoints.isEmpty
                            ? 'Belum ada titik tersimpan.'
                            : 'Semua titik sudah masuk rute.',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      ...unselected.map((wp) {
                        return ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: Text(wp.name),
                          subtitle: Text(
                            '${NavMath.formatDecimal(wp.latitude)}, '
                            '${NavMath.formatDecimal(wp.longitude)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => _toggle(wp.id),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedWps.length < 2
                        ? 'Pilih minimal 2 titik.'
                        : '${selectedWps.length} titik · '
                            '${selectedWps.length - 1} kaki · '
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
                        // Ambil service sebelum await (konteks bisa
                        // tidak mounted lagi setelah penyimpanan).
                        final settings =
                            context.read<SettingsService>();
                        final route = widget.existingRoute?.copyWith(
                              name: _nameController.text.trim(),
                              waypointIds: List.of(_selected),
                              speedKnots: _speedKnots,
                            ) ??
                            RoutePlan(
                              id: 'rt_${DateTime.now().microsecondsSinceEpoch}',
                              name: _nameController.text.trim(),
                              waypointIds: List.of(_selected),
                              speedKnots: _speedKnots,
                              createdAt: DateTime.now(),
                            );
                        await nav.saveRoute(route);
                        // Kecepatan ini disimpan sebagai kecepatan
                        // jelajah untuk rute berikutnya.
                        await settings
                            .setCruiseSpeedKnots(_speedKnots);
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    : null,
                icon: const Icon(Icons.save),
                label: Text(
                  isEditing ? 'Simpan perubahan' : 'Simpan rute',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris titik dalam rute: nomor urut, nama, koordinat, info
/// kaki dari titik sebelumnya (bearing + jarak), tombol ubah/hapus,
/// dan gagang seret untuk mengubah urutan.
class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    super.key,
    required this.waypoint,
    required this.number,
    required this.legFromPrevious,
    required this.onEdit,
    required this.onRemove,
  });

  final Waypoint waypoint;
  final int number;
  final RouteLeg? legFromPrevious;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leg = legFromPrevious;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: number - 1,
              child: const Icon(Icons.drag_handle),
            ),
            const SizedBox(width: 4),
            CircleAvatar(
              radius: 14,
              backgroundColor: scheme.primary,
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    waypoint.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${NavMath.formatDecimal(waypoint.latitude)}, '
                    '${NavMath.formatDecimal(waypoint.longitude)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (leg != null)
                    Text(
                      'Dari titik ${number - 1}: arah '
                      '${leg.bearingDeg.toStringAsFixed(0)}° · '
                      '${NavMath.formatDistance(leg.distanceM)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Ubah nama/koordinat',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Keluarkan dari rute',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
