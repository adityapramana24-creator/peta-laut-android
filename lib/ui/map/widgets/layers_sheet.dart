import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/map_layers.dart';
import '../../../domain/models/seamark.dart';
import '../view_models/map_viewmodel.dart';
import 'gebco_legend.dart';

/// Lembar pengalih basemap + overlay (R-11).
Future<void> showLayersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const LayersSheet(),
  );
}

class LayersSheet extends StatelessWidget {
  const LayersSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MapViewModel>();
    final layers = vm.layers;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Padding(
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
            const Text(
              'Lapisan peta',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Basemap',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: BasemapKind.values.map((kind) {
                final selected = layers.basemap == kind;
                return ChoiceChip(
                  label: Text(kind.label),
                  selected: selected,
                  onSelected: (_) => vm.setBasemap(kind),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Kedalaman GEBCO (warna laut)'),
              subtitle: const Text(
                'Pewarnaan batimetri global — redup agar peta dasar '
                'tetap terbaca',
              ),
              value: layers.showGebco,
              onChanged: vm.toggleGebco,
            ),
            if (layers.showGebco)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GebcoLegend(),
              ),
            SwitchListTile(
              title: const Text('Angka kedalaman di peta'),
              subtitle: const Text(
                'Label meter langsung di peta (zoom 10 ke atas). '
                'Nilai model GEBCO grid ~450 m, bukan sounding '
                'survei; sungai tidak ada data.',
              ),
              value: layers.showDepthLabels,
              onChanged: vm.toggleDepthLabels,
            ),
            SwitchListTile(
              title: const Text('Rambu laut (OpenSeaMap)'),
              subtitle: const Text('Mercusuar, pelampung, rambu'),
              value: layers.showSeamark,
              onChanged: vm.toggleSeamark,
            ),
            SwitchListTile(
              title: const Text('Rambu laut (data OSM, bisa ditekan)'),
              subtitle: const Text(
                'Marker rambu dari OpenStreetMap (zoom 12 ke atas) — '
                'ketuk marker untuk nama, jenis, cahaya, dan posisi.',
              ),
              value: layers.showSeamarkMarkers,
              onChanged: vm.toggleSeamarkMarkers,
            ),
            if (layers.showSeamarkMarkers)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  Seamark.coverageNote,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            SwitchListTile(
              title: const Text('Radar hujan'),
              subtitle: const Text('RainViewer — data ~10 menit terakhir'),
              value: layers.showRain,
              onChanged: vm.toggleRain,
            ),
            SwitchListTile(
              title: const Text('Citra satelit NASA'),
              subtitle: const Text(
                'MODIS Terra kemarin (zoom maks 9) — citra penuh, '
                'menutupi basemap saat aktif',
              ),
              value: layers.showGibs,
              onChanged: vm.toggleGibs,
            ),
            SwitchListTile(
              title: const Text('Kapal AIS'),
              subtitle: const Text('Marker kapal di peta'),
              value: layers.showAis,
              onChanged: vm.toggleAis,
            ),
          ],
        ),
      ),
    );
  }
}
