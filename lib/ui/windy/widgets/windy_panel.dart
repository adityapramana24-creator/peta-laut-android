import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/windy.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../view_models/windy_viewmodel.dart';
import 'alert_dialog.dart';
import 'meteogram_chart.dart';
import 'wind_legend.dart';

/// Panel Angin & Prakiraan (paket Windy, R-30): pilih model,
/// partikel angin, prakiraan titik + meteogram, peringatan ambang.
Future<void> showWindyPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const WindyPanel(),
  );
}

class WindyPanel extends StatelessWidget {
  const WindyPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final windy = context.watch<WindyViewModel>();
    final mapVm = context.watch<MapViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
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
              'Angin & Prakiraan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            // -- Model prakiraan --
            const Text(
              'Model prakiraan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WindyModel.values.map((model) {
                return ChoiceChip(
                  label: Text(model.label),
                  selected: windy.model == model,
                  onSelected: (_) => windy.setModel(model),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text(
              'Model dipakai untuk prakiraan titik, grid angin, dan '
              'cuaca di rute.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 28),
            // -- Partikel angin --
            Row(
              children: [
                const Icon(Icons.air),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Partikel angin di peta',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: windy.particlesEnabled,
                  onChanged: (value) async {
                    final bounds = mapVm.visibleBounds ??
                        boundsAround(mapVm.center);
                    await windy.setParticlesEnabled(
                      value,
                      bounds: bounds,
                    );
                  },
                ),
              ],
            ),
            if (windy.gridLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Memuat grid angin…'),
                  ],
                ),
              ),
            if (windy.gridError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Grid angin gagal: ${windy.gridError}',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            if (windy.particlesEnabled && windy.grid != null) ...[
              const SizedBox(height: 8),
              Text(
                'Grid ${windy.grid!.model} · '
                '${windy.grid!.times.length} jam · '
                'diambil ${IdFormat.timeHm(windy.grid!.fetchedAt)} WIB',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: mapVm.visibleBounds == null
                    ? null
                    : () => windy.loadGrid(
                          mapVm.visibleBounds!,
                          forceRefresh: true,
                        ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat ulang grid untuk area ini'),
              ),
            ],
            if (windy.particlesEnabled) ...[
              const SizedBox(height: 8),
              const WindLegend(),
              Text(
                'Warna garis = kecepatan angin; panjang jejak juga '
                'bertambah saat angin kencang.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const Divider(height: 28),
            // -- Panah arus --
            Row(
              children: [
                const Icon(Icons.waves),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Panah arus di peta',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: windy.currentsEnabled,
                  onChanged: (value) async {
                    final bounds = mapVm.visibleBounds ??
                        boundsAround(mapVm.center);
                    await windy.setCurrentsEnabled(
                      value,
                      bounds: bounds,
                    );
                  },
                ),
              ],
            ),
            if (windy.currentGridLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Memuat grid arus…'),
                  ],
                ),
              ),
            if (windy.currentGridError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Grid arus gagal: ${windy.currentGridError}',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
            if (windy.currentsEnabled && windy.currentGrid != null) ...[
              const SizedBox(height: 8),
              Text(
                'Grid arus · '
                '${windy.currentGrid!.times.length} jam · '
                'diambil ${IdFormat.timeHm(windy.currentGrid!.fetchedAt)} WIB',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: mapVm.visibleBounds == null
                    ? null
                    : () => windy.loadCurrentGrid(
                          mapVm.visibleBounds!,
                          forceRefresh: true,
                        ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat ulang grid untuk area ini'),
              ),
            ],
            if (windy.currentsEnabled) ...[
              const SizedBox(height: 8),
              const CurrentLegend(),
              Text(
                'Panah menunjuk ke arah arus mengalir; warna = '
                'kecepatan. Model Open-Meteo resolusi ~8 km — tidak '
                'untuk navigasi pantai dan tidak menggantikan almanak '
                'nautika.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const Divider(height: 28),
            // -- Prakiraan titik --
            const Text(
              'Prakiraan di satu titik',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    // Mode pilih titik dan mode ukur saling meniadakan.
                    context
                        .read<NavigationViewModel>()
                        .setMeasureMode(false);
                    windy.setPickMode(true);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Pilih titik di peta'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      windy.loadPointForecast(mapVm.panelPoint),
                  icon: const Icon(Icons.my_location),
                  label: const Text('Di posisi saya'),
                ),
              ],
            ),
            if (windy.forecastLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (windy.forecastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Prakiraan gagal: ${windy.forecastError}',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            if (windy.pointForecast != null) ...[
              const SizedBox(height: 12),
              Text(
                'Titik: ${NavMath.formatDecimal(windy.pointForecast!.latitude)}, '
                '${NavMath.formatDecimal(windy.pointForecast!.longitude)}'
                ' · model ${windy.pointForecast!.model}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              MeteogramChart(forecast: windy.pointForecast!),
            ],
            const Divider(height: 28),
            // -- Peringatan --
            Row(
              children: [
                const Icon(Icons.notifications_active),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Peringatan cuaca',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final alert = await showAlertDialog(context);
                    if (alert != null && context.mounted) {
                      final vm = context.read<WindyViewModel>();
                      await vm.addAlert(alert);
                      // Peringatan dievaluasi terhadap prakiraan titik —
                      // bila belum ada, muat sekarang agar peringatan
                      // langsung bekerja (bukan diam selamanya).
                      if (vm.pointForecast == null && context.mounted) {
                        await vm.loadPointForecast(mapVm.panelPoint);
                      }
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            Text(
              'Diperiksa tiap 15 menit selama aplikasi terbuka, '
              'terhadap prakiraan segar di posisi kapal saat ini. '
              'Maks 1 notifikasi per 6 jam per peringatan.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (windy.alerts.isEmpty)
              Text(
                'Belum ada peringatan. Tambahkan ambang angin, '
                'gelombang, atau hujan.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              ...windy.alerts.map((alert) {
                final parts = <String>[];
                if (alert.windKnots != null) {
                  parts.add('angin > ${alert.windKnots!.toStringAsFixed(0)} kt');
                }
                if (alert.waveM != null) {
                  parts.add('gelombang > ${alert.waveM!.toStringAsFixed(1)} m');
                }
                if (alert.rainMmPerHour != null) {
                  parts.add('hujan > ${alert.rainMmPerHour!.toStringAsFixed(1)} mm/jam');
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(alert.name),
                    subtitle: Text(parts.join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: alert.enabled,
                          onChanged: (v) =>
                              windy.toggleAlert(alert.id, v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: 'Ubah',
                          onPressed: () async {
                            final updated = await showAlertDialog(
                              context,
                              existing: alert,
                            );
                            if (updated != null && context.mounted) {
                              await context
                                  .read<WindyViewModel>()
                                  .updateAlert(updated);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Hapus',
                          onPressed: () => windy.deleteAlert(alert.id),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: windy.alerts
                      .where((a) => a.enabled)
                      .isEmpty
                  ? null
                  : () => windy.evaluateNow(mapVm.panelPoint),
              icon: const Icon(Icons.search),
              label: const Text('Periksa sekarang'),
            ),
            if (windy.alerts.where((a) => a.enabled).isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Aktifkan minimal satu peringatan untuk memeriksa.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Batas peta untuk grid angin dari tengah peta bila bounds belum ada.
LatLngBounds boundsAround(LatLng center, {double spanDeg = 2.0}) {
  return LatLngBounds(
    LatLng(center.latitude - spanDeg / 2, center.longitude - spanDeg / 2),
    LatLng(center.latitude + spanDeg / 2, center.longitude + spanDeg / 2),
  );
}
