import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_constants.dart';
import '../../../data/services/offline_tile_service.dart';
import '../../../domain/models/map_layers.dart';
import '../../../domain/models/port.dart';
import '../../../utils/formatters.dart';
import '../../../utils/tile_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../view_models/offline_viewmodel.dart';

/// Panel Peta Offline (R-32/R-33): status online, simpan area yang
/// tampil di layar (zoom saat ini, maks 400 tile), daftar wilayah
/// tersimpan, dan catatan auto-simpan cache 500 MB.
Future<void> showOfflineSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const OfflineSheet(),
  );
}

class OfflineSheet extends StatefulWidget {
  const OfflineSheet({super.key});

  @override
  State<OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<OfflineSheet> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final mapVm = context.read<MapViewModel>();
    final nearest = Port.nearest(
      mapVm.center.latitude,
      mapVm.center.longitude,
    );
    _nameController = TextEditingController(
      text: '${nearest.name} ${IdFormat.dateShort(DateTime.now())}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflineViewModel>();
    final mapVm = context.watch<MapViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final bounds = mapVm.visibleBounds;
    final zoom = mapVm.zoom.round().clamp(3, 19);
    final basemap = mapVm.layers.basemap;

    TileRange? range;
    if (bounds != null) {
      range = TileMath.rangeForBounds(
        south: bounds.southWest.latitude,
        west: bounds.southWest.longitude,
        north: bounds.northEast.latitude,
        east: bounds.northEast.longitude,
        zoom: zoom,
      );
    }
    final tooWide =
        range != null && range.count > OfflineTileService.maxTilesPerArea;
    final savedHere = offline.isAreaSaved(
      centerLat: mapVm.center.latitude,
      centerLon: mapVm.center.longitude,
      zoom: zoom,
      basemap: basemap.name,
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
            Row(
              children: [
                const Text(
                  'Peta Offline',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    offline.isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: offline.isOnline
                      ? scheme.primaryContainer
                      : scheme.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tile yang pernah dilihat tersimpan otomatis di HP '
              '(cache maks 500 MB) dan tampil saat offline. Area yang '
              'disimpan di bawah ini tampil sebagai lapisan di atas '
              'basemap yang sama.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 28),
            const Text(
              'Simpan area yang tampil',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (range == null)
              const Text('Peta belum siap — tutup lalu buka lagi.')
            else ...[
              Text(
                'Basemap ${basemap.label} · zoom $zoom · '
                '${range.count} tile'
                '${savedHere ? ' · area ini sudah tersimpan' : ''}',
              ),
              if (tooWide)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Terlalu luas (maks ${OfflineTileService.maxTilesPerArea} tile). '
                    'Perbesar peta (zoom in) dulu.',
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama area',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (offline.saving && offline.saveProgress != null) ...[
                LinearProgressIndicator(
                  value: offline.saveProgress!.total > 0
                      ? offline.saveProgress!.done /
                          offline.saveProgress!.total
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  'Mengunduh ${offline.saveProgress!.done}/'
                  '${offline.saveProgress!.total} tile '
                  '(${offline.saveProgress!.percent}%)'
                  '${offline.saveProgress!.failed > 0 ? ' · ${offline.saveProgress!.failed} gagal' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: tooWide || !offline.isOnline
                        ? null
                        : () => offline.saveCurrentArea(
                              bounds: bounds,
                              zoom: mapVm.zoom,
                              basemap: basemap.name,
                              urlTemplate: basemap.urlTemplate,
                              name: _nameController.text.trim().isEmpty
                                  ? 'Area tersimpan'
                                  : _nameController.text.trim(),
                            ),
                    icon: const Icon(Icons.download),
                    label: const Text('Simpan area ini'),
                  ),
                ),
              if (!offline.isOnline)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tidak ada internet — area tidak dapat diunduh.',
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (offline.saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    offline.saveError!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
            ],
            const Divider(height: 28),
            const Text(
              'Wilayah tersimpan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (offline.areas.isEmpty)
              Text(
                'Belum ada wilayah tersimpan.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              ...offline.areas.map((area) {
                var basemapLabel = area.basemap;
                for (final b in BasemapKind.values) {
                  if (b.name == area.basemap) basemapLabel = b.label;
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.map),
                    title: Text(area.name),
                    subtitle: Text(
                      '${IdFormat.dateTimeShort(area.savedAt)} · '
                      'zoom ${area.zoom} · $basemapLabel\n'
                      '${area.tileCount} tile · ${area.sizeLabel}'
                      '${area.failedTiles > 0 ? ' · ${area.failedTiles} tile gagal' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility),
                          tooltip: 'Lihat di peta',
                          onPressed: () {
                            context.read<MapViewModel>().moveTo(
                                  LatLng(area.centerLat, area.centerLon),
                                  zoom: area.zoom.toDouble(),
                                );
                            Navigator.of(context).pop();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Hapus area',
                          onPressed: () async {
                            final ok = await _confirmDelete(
                              context,
                              'Hapus wilayah "${area.name}" '
                              '(${area.tileCount} tile)?',
                            );
                            if (ok && context.mounted) {
                              await context
                                  .read<OfflineViewModel>()
                                  .deleteArea(area.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text(
              'Hanya tile yang tampil di layar pada zoom saat ini yang '
              'diunduh — sesuai kebijakan server tile (tanpa unduh '
              'massal). Tile tersimpan hanya tampil kembali pada zoom '
              'yang sama; pakai tombol Lihat pada area untuk melompat '
              'ke zoom-nya. Cache tile otomatis: maks '
              '${(AppConstants.tileCacheMaxBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
