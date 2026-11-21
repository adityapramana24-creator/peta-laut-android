import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/sea_regions.dart';
import '../../../domain/models/bmkg_maritim.dart';
import 'bmkg_wave_style.dart';

/// Marker gelombang BMKG di peta (ronde 2, fase 2 — permintaan user:
/// "perkiraan gelombang bisa langsung muncul di peta").
///
/// Widget ini MURNI tampilan: menerima prakiraan dari
/// BmkgMaritimViewModel (loader terpisah — fetch, cache, refresh
/// 3 jam, resume) dan melukis satu MarkerLayer. Satu marker per
/// wilayah berkode BMKG di TITIK TENGAH wilayahnya
/// ([SeaRegion.latitude]/[SeaRegion.longitude]): pil berwarna
/// kategori BMKG berisi tinggi gelombang saat ini ("2,0 m").
/// Ketuk marker -> [onRegionTap] (koordinator membuka lembar
/// prakiraan wilayah lengkap via showBmkgRegionSheet).
///
/// Kejujuran tampilan:
/// - wilayah tanpa prakiraan (fetch gagal + tanpa cache) TIDAK
///   bermarker — jangan tampilkan angka karangan;
/// - prakiraan KEDALUWARSA (lewat valid_to) tampil pil ABU-ABU
///   (bukan warna kategori) — lembar detail melabelinya jelas;
/// - pil kecil (72x28) agar tidak menutupi peta; nama wilayah
///   hanya muncul di lembar detail, bukan di peta.
class BmkgWaveMarkers extends StatelessWidget {
  const BmkgWaveMarkers({
    super.key,
    required this.forecasts,
    required this.onRegionTap,
    this.enabled = true,
  });

  /// Prakiraan per wilayah, kunci = [SeaRegion.id] (kode M.xx).
  final Map<String, BmkgMaritimForecast> forecasts;

  /// Dipanggil saat marker wilayah diketuk.
  final void Function(SeaRegion region, BmkgMaritimForecast forecast)
      onRegionTap;

  /// False -> tidak ada marker sama sekali (saklar lapisan).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || forecasts.isEmpty) return const SizedBox.shrink();
    final markers = <Marker>[];
    for (final region in kSeaRegions) {
      final forecast = forecasts[region.id];
      if (forecast == null) continue;
      final current = forecast.current;
      final height = current?.waveHeightM;
      if (height == null) continue;
      final expired = forecast.isExpired;
      final color = expired
          ? Colors.grey
          : bmkgWaveCategoryColor(current?.waveCat);
      markers.add(
        Marker(
          point: LatLng(region.latitude, region.longitude),
          width: 72,
          height: 28,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onRegionTap(region, forecast),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: expired ? 0.75 : 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                '${height.toStringAsFixed(1)} m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (markers.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: markers);
  }
}
