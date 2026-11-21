import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../data/repositories/ais_repository.dart';
import '../../../data/services/ship_ais_bluetooth_service.dart';
import '../../../data/services/ship_ais_service.dart';
import '../../../domain/models/ais_target_status.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/cpa_math.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../view_models/ais_viewmodel.dart';
import 'ship_ais_panel.dart';
import 'vessel_sheet.dart';

/// Panel Kapal AIS (R-18, R-19): status koneksi + daftar kapal di area.
/// Judul panel sengaja generik ("Kapal (AIS)") — sumber data ada DUA:
/// Internet/AISStream (seksi di bawah, panel ini) + Offline/AIS kapal
/// (panel pekerja D, dibuka dari pemilih sumber di bawah judul).
/// Kunci TIDAK PERNAH ditampilkan kembali setelah disimpan.
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
            const SizedBox(height: 4),
            // RONDE 2 (S-8/S-9): pemilih sumber AIS — Internet (AISStream,
            // seksi di bawah ini) vs Offline (AIS kapal, panel pekerja D).
            const _SourceSelector(),
            const SizedBox(height: 8),
            // Label seksi sumber Internet.
            Row(
              children: [
                Icon(
                  Icons.wifi,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Internet · AISStream',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
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

/// Pemilih sumber AIS (RONDE 2, S-9): dua tombol berdampingan.
/// "Internet" = seksi AISStream yang tampil di panel ini (selalu
/// terpilih secara visual — menekan tidak berbuat apa-apa).
/// "Offline · AIS kapal" = membuka panel AIS kapal (WiFi/Bluetooth)
/// sebagai lembar kedua; sublabel menampilkan status koneksi kapal
/// secara live. Kedua sumber bisa aktif bersamaan dan merge ke peta
/// yang sama (keputusan S-9: tanpa jeda-otomatis AISStream — user
/// mengendalikan masing-masing lewat tombol Putuskan-nya).
class _SourceSelector extends StatelessWidget {
  const _SourceSelector();

  @override
  Widget build(BuildContext context) {
    final shipService = context.read<ShipAisService>();
    final btService = context.read<ShipAisBluetoothService?>();
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<ShipAisConnectionState>(
      stream: shipService.connectionStateStream,
      initialData: shipService.connectionState,
      builder: (context, snapshot) {
        final shipState =
            snapshot.data ?? ShipAisConnectionState.disconnected;
        final shipConnected =
            shipState == ShipAisConnectionState.connected;
        final shipColor = switch (shipState) {
          ShipAisConnectionState.connected => scheme.primary,
          ShipAisConnectionState.connecting ||
          ShipAisConnectionState.reconnecting => scheme.tertiary,
          ShipAisConnectionState.error => scheme.error,
          ShipAisConnectionState.disconnected =>
            scheme.onSurfaceVariant,
        };
        return Row(
          children: [
            Expanded(
              child: _SourceButton(
                icon: Icons.wifi,
                label: 'Internet',
                sublabel: 'AISStream',
                selected: true,
                onTap: null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SourceButton(
                icon: Icons.directions_boat,
                label: 'Offline · AIS kapal',
                sublabel: shipState.label,
                selected: shipConnected,
                statusColor: shipColor,
                onTap: () => showShipAisPanel(
                  context,
                  service: shipService,
                  bluetoothService: btService,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.selected,
    this.statusColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool selected;
  final Color? statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final fg = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    Text(
                      sublabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor ?? fg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      AisConnectionState.notConfigured ||
      AisConnectionState.disconnected =>
        scheme.onSurfaceVariant,
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
            'Untuk melihat kapal di sekitar lewat internet, isi kunci '
            'API AISStream (gratis). Kunci disimpan aman di perangkat '
            'ini dan tidak pernah dibagikan.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          const _KeyGuideSteps(),
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
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Belum punya kunci? Daftar gratis di aisstream.io'),
            // F-L7: pola gagal-jujur seperti tautan BMKG
            // (marine_panel): launchUrl langsung tanpa gate
            // canLaunchUrl; bila gagal, SnackBar menampilkan URL
            // + aksi Salin — jangan pernah gagal diam-diam.
            onPressed: () async {
              final url = AppConstants.aisSignupUrl;
              final uri = Uri.parse(url);
              bool opened = false;
              try {
                opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {
                opened = false;
              }
              if (opened || !context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Tidak bisa membuka browser. Salin alamat ini '
                    'dan buka manual:\n$url',
                  ),
                  duration: const Duration(seconds: 8),
                  action: SnackBarAction(
                    label: 'Salin',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Kunci gratis, tanpa kartu kredit. Aplikasi tidak pernah '
            'meminta kunci lewat chat — hanya lewat kolom di atas.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Cakupan AIS darat (terestrial) — di perairan Indonesia '
            'timur kapal yang tertangkap bisa lebih sedikit.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Catatan: koneksi aplikasi ini tanpa kompresi (keterbatasan '
            'platform) — di area sangat ramai sebagian pesan bisa '
            'terlewat.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Langkah ambil kunci gratis (aisstream.io, dicek 2026-11-21:
/// masuk dengan GitHub → Account → buat API key, kunci hanya
/// ditampilkan sekali).
class _KeyGuideSteps extends StatelessWidget {
  const _KeyGuideSteps();

  static const _steps = [
    'Buka aisstream.io di browser HP, lalu masuk dengan akun GitHub.',
    'Buka Account, buat API key baru — kunci hanya ditampilkan '
        'sekali, salin segera.',
    'Tempel kunci di kolom di bawah, lalu ketuk Simpan kunci.',
    'Status berubah "Terhubung" dan kapal di sekitar muncul di peta.',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cara ambil kunci gratis:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VesselList extends StatelessWidget {
  const _VesselList({required this.vm});

  final AisViewModel vm;

  String _diagnosticsText(AisDiagnostics d) {
    if (d.framesReceived == 0) {
      return 'Belum ada data masuk — periksa koneksi internet.';
    }
    return '${d.framesReceived} frame diterima · '
        '${d.messagesParsed} pesan kapal diproses';
  }

  @override
  Widget build(BuildContext context) {
    final mapVm = context.watch<MapViewModel>();
    final navVm = context.read<NavigationViewModel>();
    // Posisi kapal sendiri — prioritas AIVDO (AIS kapal, paling akurat),
    // lalu GPS HP, lalu tengah peta (label jujur di bawah).
    final ownShip = vm.ownShip;
    final ownShipPos = (ownShip != null && ownShip.hasPosition)
        ? LatLng(ownShip.latitude!, ownShip.longitude!)
        : null;
    final own = mapVm.ownPosition;
    final reference = ownShipPos ?? own ?? mapVm.center;
    final fromShip = ownShipPos != null;
    final fromGps = own != null;
    final nearby = vm.nearbyList(reference);
    final state = vm.state;

    // Keadaan kapal sendiri untuk CPA — AIVDO dulu (posisi/SOG/COG dari
    // transponder kapal sendiri), GPS cadangan, null bila keduanya tidak
    // ada (CPA tidak dihitung, bukan dipalsukan).
    final ownState = ownShipPos != null
        ? OwnShipState(
            latitude: ownShipPos.latitude,
            longitude: ownShipPos.longitude,
            sogKnots: ownShip!.speedKnots,
            cogDeg: ownShip.courseDeg,
          )
        : own == null
            ? null
            : OwnShipState(
                latitude: own.latitude,
                longitude: own.longitude,
                sogKnots: navVm.sogKnots,
                cogDeg: navVm.cogDeg,
              );

    if (nearby.isEmpty) {
      return _EmptyState(
        vm: vm,
        mapVm: mapVm,
        diagnosticsText: _diagnosticsText(vm.diagnostics),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${nearby.length} kapal tertangkap',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (state == AisConnectionState.connected ||
                state == AisConnectionState.connecting ||
                state == AisConnectionState.reconnecting)
              TextButton.icon(
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Putuskan'),
                onPressed: vm.disconnect,
              ),
            if (state == AisConnectionState.disconnected ||
                state == AisConnectionState.error)
              TextButton.icon(
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Sambungkan lagi'),
                onPressed: () =>
                    vm.retryConnection(mapVm.aisBounds),
              ),
          ],
        ),
        Text(
          fromShip
              ? 'Diurutkan dari yang terdekat dengan kapal Anda (AIS kapal)'
              : fromGps
                  ? 'Diurutkan dari yang terdekat dengan Anda'
                  : 'Diurutkan dari yang terdekat dengan tengah peta '
                      '(GPS belum aktif)',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: nearby.length,
            itemBuilder: (context, index) {
              final item = nearby[index];
              final vessel = item.vessel;
              final distance = item.distanceMeters == null
                  ? null
                  : NavMath.formatDistance(item.distanceMeters!);
              CpaResult? cpa;
              var dangerous = false;
              if (ownState != null) {
                cpa = AisTargetStatusResolver.cpaFor(
                  vessel: vessel,
                  own: ownState,
                );
                dangerous = cpa != null &&
                    AisTargetStatusResolver.isDangerous(
                      cpa,
                      cpaThresholdNm: vm.cpaThresholdNm,
                      tcpaThresholdMin: vm.tcpaThresholdMin,
                    );
              }
              // Teks bahaya dihitung di sini (bukan di dalam
              // collection-if) agar tidak bergantung pada promosi
              // null di elemen list.
              final dangerText = (dangerous && cpa != null)
                  ? 'BAHAYA: CPA '
                      '${cpa.cpaNm.toStringAsFixed(1)} nm · '
                      '${CpaMath.formatTcpa(cpa.tcpaMinutes)}'
                  : null;
              return ListTile(
                leading: Icon(
                  dangerous
                      ? Icons.warning_amber_rounded
                      : Icons.directions_boat,
                  color: dangerous
                      ? scheme.error
                      : scheme.primary,
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
                    if (dangerText != null) dangerText,
                  ].join(' · '),
                  style: dangerous
                      ? TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
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
        Row(
          children: [
            TextButton(
              onPressed: vm.deleteKey,
              child: const Text('Hapus kunci AIS'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Keadaan kosong yang jujur per status koneksi — bukan satu pesan
/// generik untuk semua keadaan.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.vm,
    required this.mapVm,
    required this.diagnosticsText,
  });

  final AisViewModel vm;
  final MapViewModel mapVm;
  final String diagnosticsText;

  @override
  Widget build(BuildContext context) {
    final state = vm.state;
    final scheme = Theme.of(context).colorScheme;

    if (state == AisConnectionState.connecting ||
        state == AisConnectionState.reconnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Menghubungkan ke AISStream…'),
          ],
        ),
      );
    }

    if (state == AisConnectionState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                vm.statusMessage ?? 'Koneksi AIS gagal.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Coba lagi'),
              onPressed: () =>
                  vm.retryConnection(mapVm.aisBounds),
            ),
            TextButton(
              onPressed: vm.deleteKey,
              child: const Text('Hapus kunci AIS'),
            ),
          ],
        ),
      );
    }

    if (state == AisConnectionState.disconnected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Koneksi AISStream diputuskan.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Sambungkan lagi'),
              onPressed: () =>
                  vm.retryConnection(mapVm.aisBounds),
            ),
            TextButton(
              onPressed: vm.deleteKey,
              child: const Text('Hapus kunci AIS'),
            ),
          ],
        ),
      );
    }

    // Terhubung tapi belum ada kapal.
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
          const SizedBox(height: 8),
          Text(
            diagnosticsText,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Putuskan'),
                onPressed: vm.disconnect,
              ),
              TextButton(
                onPressed: vm.deleteKey,
                child: const Text('Hapus kunci AIS'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
