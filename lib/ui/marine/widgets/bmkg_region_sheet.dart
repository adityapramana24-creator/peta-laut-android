import 'package:flutter/material.dart';

import '../../../config/sea_regions.dart';
import '../../../domain/models/bmkg_maritim.dart';
import '../../../utils/formatters.dart';
import '../../../utils/wib_clock.dart';
import 'bmkg_wave_style.dart';

/// Lembar prakiraan wilayah lengkap (dari marker gelombang di peta).
/// Menampilkan prakiraan resmi BMKG: gelombang saat ini + per jam
/// hari ini + per 3 jam hari ke-2 s.d. ke-4, angin, arus, dan
/// stempel berlaku. Semua waktu dalam WIB (data BMKG UTC+0,
/// dikonversi +7 jam) dengan label zona yang jelas.
///
/// [BmkgForecastBody] dipakai ulang oleh seksi wilayah di
/// panel Gelombang (marine_panel.dart) agar isi prakiraan BMKG
/// tampil sama di peta maupun di panel.
Future<void> showBmkgRegionSheet(
  BuildContext context, {
  required SeaRegion region,
  required BmkgMaritimForecast forecast,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BmkgRegionSheet(region: region, forecast: forecast),
  );
}

class BmkgRegionSheet extends StatelessWidget {
  const BmkgRegionSheet({
    super.key,
    required this.region,
    required this.forecast,
  });

  final SeaRegion region;
  final BmkgMaritimForecast forecast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.68;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                Icon(Icons.waves, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    region.name,
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
            Text(
              'Kode BMKG ${region.bmkgCode ?? '-'}'
              ' • Prakiraan wilayah resmi BMKG',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BmkgForecastBody(forecast: forecast),
                    const SizedBox(height: 12),
                    Text(
                      'Sumber: BMKG',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Isi prakiraan BMKG satu wilayah: stempel berlaku + kartu saat ini
/// + per jam hari ini + per 3 jam hari 2–4 + catatan kejujuran.
/// Dipakai lembar wilayah ([BmkgRegionSheet]) dan seksi wilayah
/// panel Gelombang.
class BmkgForecastBody extends StatelessWidget {
  const BmkgForecastBody({super.key, required this.forecast});

  final BmkgMaritimForecast forecast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = forecast.current;
    final expired = forecast.isExpired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (expired)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Prakiraan ini SUDAH LEWAT masa berlaku'
              '${forecast.validToUtc != null ? ' (s.d. ${IdFormat.dateTimeShort(IdFormat.toWib(forecast.validToUtc!))} WIB)' : ''}. '
              'Menunggu prakiraan baru dari BMKG — angka di bawah ini '
              'adalah prakiraan lama, bukan prakiraan berlaku.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (forecast.isStale)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Data lama (offline) — diambil '
              '${IdFormat.dateTimeShort(IdFormat.toWib(forecast.fetchedAt.toUtc()))} WIB. '
              'Muat ulang saat ada koneksi.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          _validityStamp(forecast),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (current != null) ...[
          _BmkgCurrentCard(hour: current),
          const SizedBox(height: 16),
        ],
        if (forecast.day1.isNotEmpty) ...[
          const Text(
            'Per jam hari ini',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...forecast.day1.map(
            (h) => _BmkgHourRow(hour: h),
          ),
          const SizedBox(height: 12),
        ],
        if (forecast.day2to4.isNotEmpty) ...[
          const Text(
            'Hari ke-2 s.d. ke-4 (per 3 jam)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...forecast.day2to4.map(
            (h) => _BmkgHourRow(hour: h, showDate: true),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Prakiraan resmi BMKG untuk seluruh wilayah perairan ini '
          '(bukan satu titik). API BMKG tidak menyediakan arah & '
          'periode gelombang — hanya tinggi + kategori.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// "Diterbitkan 20 Nov, 19:00 WIB · Berlaku 21 Nov, 07:00 s.d.
  /// 24 Nov, 07:00 WIB" — bagian yang datanya hilang dilewati.
  String _validityStamp(BmkgMaritimForecast f) {
    final parts = <String>[];
    if (f.issuedUtc != null) {
      parts.add(
        'Diterbitkan ${IdFormat.dateTimeShort(IdFormat.toWib(f.issuedUtc!))} WIB',
      );
    }
    if (f.validFromUtc != null && f.validToUtc != null) {
      parts.add(
        'Berlaku ${IdFormat.dateTimeShort(IdFormat.toWib(f.validFromUtc!))} '
        's.d. ${IdFormat.dateTimeShort(IdFormat.toWib(f.validToUtc!))} WIB',
      );
    }
    if (parts.isEmpty) return 'Masa berlaku tidak diketahui.';
    return parts.join(' · ');
  }
}

class _BmkgCurrentCard extends StatelessWidget {
  const _BmkgCurrentCard({required this.hour});

  final BmkgMaritimHour hour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoryColor = bmkgWaveCategoryColor(hour.waveCat);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.waves, size: 32, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hour.waveHeightM != null)
                        Text(
                          '${hour.waveHeightM!.toStringAsFixed(1)} m',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      Text(
                        'Saat ini (${IdFormat.timeHm(hour.timeWib)} WIB)',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (hour.waveCat != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Chip(
                            label: Text(
                              'Kategori BMKG: ${hour.waveCat}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            backgroundColor: categoryColor,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hour.tempAvgC != null)
                  Text(
                    '${hour.tempAvgC!.toStringAsFixed(0)}°C',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (hour.weather != null)
                  _Fact(label: 'Cuaca', value: hour.weather!),
                if (hour.windFrom != null && hour.windSpeedKt != null)
                  _Fact(
                    label: 'Angin dari',
                    value:
                        '${hour.windFrom} ${hour.windSpeedKt!.toStringAsFixed(0)} kt'
                        '${hour.windGustKt != null ? ' (gust ${hour.windGustKt!.toStringAsFixed(0)} kt)' : ''}',
                  ),
                if (hour.currentTo != null && hour.currentSpeedKt != null)
                  _Fact(
                    label: 'Arus ke',
                    value:
                        '${hour.currentTo} ${hour.currentSpeedKt!.toStringAsFixed(1)} kt',
                  ),
                if (hour.rhAvgPct != null)
                  _Fact(
                    label: 'Kelembapan',
                    value: '${hour.rhAvgPct!.toStringAsFixed(0)}%',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

class _BmkgHourRow extends StatelessWidget {
  const _BmkgHourRow({required this.hour, this.showDate = false});

  final BmkgMaritimHour hour;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wib = hour.timeWib;
    final nowWib = WibClock.now();
    final isToday = wib.day == nowWib.day &&
        wib.month == nowWib.month &&
        wib.year == nowWib.year;
    final timeLabel = (showDate && !isToday)
        ? '${IdFormat.dateShort(wib)} ${IdFormat.timeHm(wib)}'
        : IdFormat.timeHm(wib);
    final details = <String>[];
    if (hour.weather != null) details.add(hour.weather!);
    if (hour.windFrom != null && hour.windSpeedKt != null) {
      details.add(
        'Angin dari ${hour.windFrom} '
        '${hour.windSpeedKt!.toStringAsFixed(0)} kt',
      );
    }
    if (hour.currentTo != null && hour.currentSpeedKt != null) {
      details.add(
        'Arus ke ${hour.currentTo} '
        '${hour.currentSpeedKt!.toStringAsFixed(1)} kt',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 76, child: Text(timeLabel)),
              Expanded(
                child: Text(
                  hour.waveHeightM == null
                      ? '-'
                      : '${hour.waveHeightM!.toStringAsFixed(1)} m',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hour.waveCat != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: bmkgWaveCategoryColor(hour.waveCat),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hour.waveCat!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 76),
              child: Text(
                details.join(' • '),
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
