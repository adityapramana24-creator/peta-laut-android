import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../view_models/navigation_viewmodel.dart';

/// Lembar Jangkar & MOB: alarm jangkar (radius + posisi) dan
/// tombol MOB + daftar tanda MOB.
Future<void> showAnchorMobSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const AnchorMobSheet(),
  );
}

class AnchorMobSheet extends StatefulWidget {
  const AnchorMobSheet({super.key});

  @override
  State<AnchorMobSheet> createState() => _AnchorMobSheetState();
}

class _AnchorMobSheetState extends State<AnchorMobSheet> {
  static const _radii = [30.0, 50.0, 100.0, 200.0];
  double _radiusM = 100;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final mapVm = context.watch<MapViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final anchor = nav.anchor;
    final own = nav.ownPosition;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
            const Text(
              'Jangkar & MOB',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            // -- Alarm jangkar --
            Row(
              children: [
                const Icon(Icons.anchor),
                const SizedBox(width: 8),
                const Text(
                  'Alarm jangkar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (anchor != null)
                  Chip(
                    label: Text(
                      anchor.armed ? 'Aktif' : 'Mati',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: anchor.armed
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (anchor != null) ...[
              Text(
                'Titik jangkar: '
                '${NavMath.formatDecimal(anchor.latitude)}, '
                '${NavMath.formatDecimal(anchor.longitude)}',
              ),
              const SizedBox(height: 8),
              const Text('Radius:'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: _radii.map((r) {
                  final selected = anchor.radiusM == r;
                  return ChoiceChip(
                    label: Text('${r.toStringAsFixed(0)} m'),
                    selected: selected,
                    onSelected: (_) {
                      if (!selected) {
                        nav.setAnchor(
                          latitude: anchor.latitude,
                          longitude: anchor.longitude,
                          radiusM: r,
                        );
                      }
                    },
                  );
                }).toList(),
              ),
              if (nav.anchorDistanceM != null)
                Text(
                  'Jarak kapal dari jangkar sekarang: '
                  '${nav.anchorDistanceM!.toStringAsFixed(0)} m',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: nav.anchorAlarm ? scheme.error : null,
                  ),
                ),
              if (nav.anchorAlarm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ALARM: kapal di luar radius jangkar!',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (!nav.anchorAlarm && nav.anchorSilenced)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Alarm dibisukan — bunyi lagi bila kapal kembali '
                    'ke dalam radius lalu keluar lagi.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (anchor.armed)
                    FilledButton.icon(
                      onPressed: () => nav.disarmAnchor(),
                      icon: const Icon(Icons.notifications_off),
                      label: const Text('Matikan alarm'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => nav.setAnchor(
                        latitude: anchor.latitude,
                        longitude: anchor.longitude,
                        radiusM: anchor.radiusM,
                      ),
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Hidupkan lagi'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => nav.clearAnchor(),
                    icon: const Icon(Icons.delete),
                    label: const Text('Hapus jangkar'),
                  ),
                  if (nav.anchorAlarm)
                    OutlinedButton.icon(
                      onPressed: () => nav.silenceAnchorAlarm(),
                      icon: const Icon(Icons.volume_off),
                      label: const Text('Diamkan alarm'),
                    ),
                ],
              ),
            ] else ...[
              const Text('Pilih radius, lalu pasang jangkar:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _radii.map((r) {
                  final selected = _radiusM == r;
                  return ChoiceChip(
                    label: Text('${r.toStringAsFixed(0)} m'),
                    selected: selected,
                    onSelected: (_) => setState(() => _radiusM = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: own == null
                        ? null
                        : () => nav.setAnchor(
                              latitude: own.latitude,
                              longitude: own.longitude,
                              radiusM: _radiusM,
                            ),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Pasang di posisi saya'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => nav.setAnchor(
                      latitude: mapVm.center.latitude,
                      longitude: mapVm.center.longitude,
                      radiusM: _radiusM,
                    ),
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('Pasang di tengah peta'),
                  ),
                ],
              ),
              if (own == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Posisi saya belum tersedia — nyalakan GPS, atau '
                    'pasang jangkar di tengah peta.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'Alarm bekerja selama aplikasi terbuka. Bila aplikasi '
              'ditutup, alarm tidak berjalan.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 32),
            // -- MOB --
            Row(
              children: [
                Icon(Icons.warning_amber, color: scheme.error),
                const SizedBox(width: 8),
                const Text(
                  'MOB (Man Overboard)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Tekan tombol merah bila ada orang jatuh ke laut — '
              'posisi dan waktunya langsung ditandai di peta.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              own != null
                  ? 'Posisi yang ditandai: posisi saya (GPS).'
                  : 'GPS belum tersedia — yang ditandai adalah '
                      'tengah peta.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final point = own ?? mapVm.center;
                  nav.addMobMark(point);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.person_pin_circle, size: 28),
                label: const Text(
                  'MOB — Tandai posisi sekarang',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (nav.mobMarks.isEmpty)
              Text(
                'Belum ada tanda MOB.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              ...nav.mobMarks.map((mark) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.person_pin_circle,
                      color: scheme.error,
                    ),
                    title: Text(
                      IdFormat.dateTimeShort(mark.recordedAt),
                    ),
                    subtitle: Text(
                      '${NavMath.formatDecimal(mark.latitude)}, '
                      '${NavMath.formatDecimal(mark.longitude)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          tooltip: 'Lihat di peta',
                          onPressed: () {
                            context.read<MapViewModel>().moveTo(
                                  LatLng(mark.latitude, mark.longitude),
                                  zoom: 14,
                                );
                            Navigator.of(context).pop();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Hapus tanda',
                          onPressed: () => nav.deleteMobMark(mark.id),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
