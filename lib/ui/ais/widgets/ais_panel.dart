import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../view_models/ais_viewmodel.dart';
import 'vessel_sheet.dart';

/// Panel Kapal AIS (R-18, R-19): status koneksi + input kunci (bila
/// belum ada) + daftar kapal di area. Kunci TIDAK PERNAH ditampilkan
/// kembali setelah disimpan.
Future<void> showAisPanel(
  BuildContext context, {
  required AisViewModel viewModel,
}) {
  viewModel.init();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<AisViewModel>.value(
      value: viewModel,
      child: const AisPanel(),
    ),
  ).then((_) => viewModel.dispose());
}

class AisPanel extends StatefulWidget {
  const AisPanel({super.key});

  @override
  State<AisPanel> createState() => _AisPanelState();
}

class _AisPanelState extends State<AisPanel> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AisViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.68;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
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
                Icon(Icons.directions_boat, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Kapal (AIS)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(state: vm.state),
                const Spacer(),
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vm.statusMessage != null)
              _StatusMessage(
                message: vm.statusMessage!,
                isError: vm.statusIsError,
              ),
            Expanded(
              child: !vm.keyChecked
                  ? const Center(child: CircularProgressIndicator())
                  : vm.hasKey
                      ? _VesselList(vm: vm)
                      : _KeyInputSection(
                          controller: _keyController,
                          vm: vm,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});

  final AisConnectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      AisConnectionState.connected => scheme.primary,
      AisConnectionState.connecting ||
      AisConnectionState.reconnecting =>
        scheme.tertiary,
      AisConnectionState.error => scheme.error,
      AisConnectionState.notConfigured => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        state.label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (isError ? scheme.error : scheme.primary)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: isError ? scheme.error : scheme.onSurface,
        ),
      ),
    );
  }
}

/// Form kunci AIS — tampil jelas di panel bila kunci belum diisi
/// (pelajaran web v2: "layar AIS ada, kolom input kunci tidak ada").
class _KeyInputSection extends StatelessWidget {
  const _KeyInputSection({required this.controller, required this.vm});

  final TextEditingController controller;
  final AisViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mapVm = context.read<MapViewModel>();
    final saving = vm.saveKeyCommand.running;
    final testing = vm.testCommand.running;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Untuk melihat kapal di sekitar, isi kunci API AISStream '
            '(gratis). Kunci disimpan aman di perangkat ini dan tidak '
            'pernah dibagikan.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Kunci API AISStream',
              hintText: 'Tempel kunci Anda di sini',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Simpan kunci'),
                onPressed: saving || testing
                    ? null
                    : () {
                        vm.saveKeyCommand.execute(
                          (controller.text, mapVm.aisBounds),
                        );
                      },
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: saving || testing
                    ? null
                    : () => vm.testCommand.execute(controller.text),
                child: const Text('Uji sambungan'),
              ),
            ],
          ),
          if (saving || testing) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Belum punya kunci? Daftar gratis di aisstream.io'),
            onPressed: () async {
              final uri = Uri.parse(AppConstants.aisSignupUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Cakupan AIS darat (terestrial) — di perairan Indonesia '
            'timur kapal yang tertangkap bisa lebih sedikit.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _VesselList extends StatelessWidget {
  const _VesselList({required this.vm});

  final AisViewModel vm;

  @override
  Widget build(BuildContext context) {
    final vessels = vm.vesselList;
    final mapVm = context.watch<MapViewModel>();
    final own = mapVm.ownPosition;

    if (vessels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_boat, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Belum ada kapal tertangkap di area ini.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Geser peta ke jalur pelayaran ramai, atau tunggu '
              'beberapa menit — kapal muncul saat memancarkan posisi.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: vm.deleteKey,
              child: const Text('Hapus kunci AIS'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Text(
              '${vessels.length} kapal tertangkap',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              onPressed: vm.deleteKey,
              child: const Text('Hapus kunci'),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: vessels.length,
            itemBuilder: (context, index) {
              final vessel = vessels[index];
              String? distance;
              if (own != null && vessel.hasPosition) {
                final meters = NavMath.distanceMeters(
                  own.latitude,
                  own.longitude,
                  vessel.latitude!,
                  vessel.longitude!,
                );
                distance =
                    '${NavMath.metersToNm(meters).toStringAsFixed(1)} mil laut';
              }
              return ListTile(
                leading: Icon(
                  Icons.directions_boat,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(vessel.displayName),
                subtitle: Text(
                  [
                    'MMSI ${vessel.mmsi}',
                    if (vessel.speedKnots != null)
                      '${vessel.speedKnots!.toStringAsFixed(1)} kt',
                    if (vessel.courseDeg != null)
                      'haluan ${vessel.courseDeg!.toStringAsFixed(0)}°',
                    if (distance != null) distance,
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  showVesselSheet(context, vessel);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
