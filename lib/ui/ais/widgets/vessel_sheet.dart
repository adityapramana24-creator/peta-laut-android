import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/ais_repository.dart';
import '../../../data/services/ais_alert_settings.dart';
import '../../../domain/models/ais_target_status.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/cpa_math.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../map/view_models/map_viewmodel.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';

/// Lembar detail satu kapal (dari marker peta / daftar panel AIS).
/// Menampilkan detail lengkap ala AIS sungguhan: nama, MMSI, tipe,
/// SOG/COG/heading, status navigasi, tujuan + ETA, dimensi, jarak,
/// dan CPA/TCPA terhadap kapal sendiri bila GPS memberi gerak.
Future<void> showVesselSheet(BuildContext context, Vessel vessel) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => VesselSheet(vessel: vessel),
  );
}

class VesselSheet extends StatefulWidget {
  const VesselSheet({super.key, required this.vessel});

  final Vessel vessel;

  @override
  State<VesselSheet> createState() => _VesselSheetState();
}

class _VesselSheetState extends State<VesselSheet> {
  double _cpaThresholdNm =
      AisTargetStatusResolver.defaultCpaThresholdNm;
  double _tcpaThresholdMin =
      AisTargetStatusResolver.defaultTcpaThresholdMin;

  @override
  void initState() {
    super.initState();
    AisAlertSettings().load().then((thresholds) {
      if (!mounted) return;
      setState(() {
        _cpaThresholdNm = thresholds.$1;
        _tcpaThresholdMin = thresholds.$2;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final vessel = widget.vessel;
    final scheme = Theme.of(context).colorScheme;
    final mapVm = context.read<MapViewModel>();
    final navVm = context.read<NavigationViewModel>();
    // Posisi kapal sendiri — prioritas AIVDO (AIS kapal, paling akurat),
    // lalu GPS HP, lalu tengah peta (label jujur di bawah).
    final ownShip = context.read<AisRepository>().ownShip;
    final ownShipPos = (ownShip != null && ownShip.hasPosition)
        ? LatLng(ownShip.latitude!, ownShip.longitude!)
        : null;
    final own = mapVm.ownPosition;
    final reference = ownShipPos ?? own ?? mapVm.center;
    final fromShip = ownShipPos != null;
    final fromGps = own != null;

    // Jarak dari posisi sendiri (atau tengah peta — label jujur).
    double? distanceM;
    if (vessel.hasPosition) {
      distanceM = NavMath.distanceMeters(
        reference.latitude,
        reference.longitude,
        vessel.latitude!,
        vessel.longitude!,
      );
    }

    // CPA/TCPA — AIVDO dulu (posisi/SOG/COG dari transponder kapal
    // sendiri), GPS cadangan, tidak dihitung bila keduanya tidak ada.
    CpaResult? cpa;
    var dangerous = false;
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
    if (ownState != null) {
      cpa = AisTargetStatusResolver.cpaFor(vessel: vessel, own: ownState);
      dangerous = cpa != null &&
          AisTargetStatusResolver.isDangerous(
            cpa,
            cpaThresholdNm: _cpaThresholdNm,
            tcpaThresholdMin: _tcpaThresholdMin,
          );
    }
    // Teks banner dihitung di sini (bukan di dalam collection-if)
    // agar tidak bergantung pada promosi null di elemen spread.
    final dangerText = (dangerous && cpa != null)
        ? 'TARGET BERBAHAYA — CPA '
            '${cpa.cpaNm.toStringAsFixed(1)} nm dalam '
            '${CpaMath.formatTcpa(cpa.tcpaMinutes)}'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
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
            Row(
              children: [
                Icon(
                  dangerous
                      ? Icons.warning_amber_rounded
                      : Icons.directions_boat,
                  color: dangerous ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vessel.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (dangerText != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  dangerText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _Row(label: 'MMSI', value: '${vessel.mmsi}'),
            if (vessel.shipTypeLabel != null)
              _Row(label: 'Tipe kapal', value: vessel.shipTypeLabel!),
            if (vessel.navStatusLabel != null)
              _Row(label: 'Status', value: vessel.navStatusLabel!),
            if (vessel.hasPosition) ...[
              _Row(
                label: 'Posisi',
                value:
                    '${NavMath.formatDecimal(vessel.latitude!, fractionDigits: 5)}, '
                    '${NavMath.formatDecimal(vessel.longitude!, fractionDigits: 5)}',
              ),
              _Row(
                label: '',
                value: NavMath.formatLatLonDms(
                  vessel.latitude!,
                  vessel.longitude!,
                ),
              ),
            ],
            if (distanceM != null)
              _Row(
                label: fromShip
                    ? 'Jarak dari kapal Anda'
                    : fromGps
                        ? 'Jarak dari Anda'
                        : 'Jarak',
                value:
                    '${NavMath.formatDistance(distanceM)}${fromShip ? ' (AIS kapal)' : fromGps ? '' : ' (dari tengah peta)'}',
              ),
            if (vessel.speedKnots != null)
              _Row(
                label: 'Kecepatan',
                value: '${vessel.speedKnots!.toStringAsFixed(1)} knot',
              ),
            if (vessel.courseDeg != null)
              _Row(
                label: 'Haluan (COG)',
                value:
                    '${vessel.courseDeg!.toStringAsFixed(0)}° '
                    '(${NavMath.compassPoint(vessel.courseDeg!)})',
              ),
            if (vessel.headingDeg != null)
              _Row(
                label: 'Arah hadap',
                value: '${vessel.headingDeg!.toStringAsFixed(0)}°',
              ),
            if (vessel.isTurning)
              const _Row(
                label: 'Manuver',
                value: 'Berbelok (indikator ROT)',
              ),
            _Row(
              label: 'CPA / TCPA',
              value: _cpaText(cpa, own),
            ),
            if (vessel.hasDimensions)
              _Row(
                label: 'Dimensi',
                value:
                    '${vessel.lengthM!.toStringAsFixed(0)} × '
                    '${vessel.beamM!.toStringAsFixed(0)} m',
              ),
            if (vessel.callsign != null)
              _Row(label: 'Callsign', value: vessel.callsign!),
            if (vessel.imoNumber != null)
              _Row(label: 'IMO', value: '${vessel.imoNumber}'),
            if (vessel.destination != null)
              _Row(label: 'Tujuan', value: vessel.destination!),
            if (vessel.eta != null)
              _Row(label: 'ETA', value: vessel.eta!),
            if (vessel.lastSeen != null)
              _Row(
                label: 'Terakhir terlihat',
                value:
                    '${IdFormat.dateTimeShort(IdFormat.toWib(vessel.lastSeen!.toUtc()))} WIB',
              ),
            const SizedBox(height: 12),
            if (vessel.hasPosition)
              FilledButton.icon(
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('Tampilkan di peta'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<MapViewModel>().moveTo(
                        LatLng(vessel.latitude!, vessel.longitude!),
                        zoom: 12,
                      );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Teks CPA/TCPA yang jujur: bila tidak bisa dihitung, sebut
  /// alasannya — jangan tampilkan angka palsu.
  String _cpaText(CpaResult? cpa, LatLng? own) {
    if (own == null) {
      return 'Tidak dapat dihitung — posisi GPS belum ada';
    }
    if (cpa == null) {
      return 'Tidak dapat dihitung — GPS kapal sendiri / data '
          'gerak target tidak tersedia';
    }
    if (!cpa.closing) {
      if (cpa.tcpaMinutes == null) {
        return 'Jarak stabil ${cpa.currentDistanceNm.toStringAsFixed(1)} nm '
            '(kecepatan relatif ~0)';
      }
      return 'Menjauh — jarak saat ini '
          '${cpa.currentDistanceNm.toStringAsFixed(1)} nm';
    }
    return '${cpa.cpaNm.toStringAsFixed(1)} nm dalam '
        '${CpaMath.formatTcpa(cpa.tcpaMinutes)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
