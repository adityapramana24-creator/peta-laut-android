import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/map_layers.dart';
import '../view_models/map_viewmodel.dart';
import 'gebco_legend.dart';

/// Lembar pengalih basemap + overlay (R-05, R-06).
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
              subtitle: const Text('Pewarnaan batimetri global'),
              value: layers.showGebco,
              onChanged: vm.toggleGebco,
            ),
            if (layers.showGebco)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GebcoLegend(),
              ),
            SwitchListTile(
              title: const Text('Rambu laut (OpenSeaMap)'),
              subtitle: const Text('Mercusuar, pelampung, rambu'),
              value: layers.showSeamark,
              onChanged: vm.toggleSeamark,
            ),
            SwitchListTile(
              title: const Text('Radar hujan'),
              subtitle: const Text('RainViewer — data ~10 menit terakhir'),
              value: layers.showRain,
              onChanged: vm.toggleRain,
            ),
            SwitchListTile(
              title: const Text('Citra satelit NASA'),
              subtitle: const Text('MODIS Terra kemarin (zoom maks 9)'),
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
