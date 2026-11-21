import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../config/sea_regions.dart';
import '../../../domain/models/marine.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../core/widgets/data_source_footer.dart';
import '../view_models/marine_viewmodel.dart';
import 'bmkg_region_sheet.dart';

/// Panel Gelombang (R-15): Open-Meteo Marine 3 hari + arus/swell/SST.
/// Titik darat -> pesan "tidak ada data", BUKAN 0.
/// Ronde 2: DITAMBAH ramalan per wilayah laut (titik tengah wilayah) —
/// ramalan titik posisi user tetap ada dan tidak berubah perilakunya.
Future<void> showMarinePanel(
  BuildContext context, {
  required LatLng point,
  required MarineViewModel viewModel,
}) {
  viewModel.load(point);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<MarineViewModel>.value(
      value: viewModel,
      child: const MarinePanel(),
    ),
  ).then((_) => viewModel.dispose());
}

class MarinePanel extends StatelessWidget {
  const MarinePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MarineViewModel>();
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
                Icon(Icons.water, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Gelombang',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (vm.point != null)
              Text(
                'Titik: ${NavMath.formatDecimal(vm.point!.latitude, fractionDigits: 4)}, '
                '${NavMath.formatDecimal(vm.point!.longitude, fractionDigits: 4)}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _Body(vm: vm)),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vm});

  final MarineViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.loading && vm.forecast == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Memuat data gelombang…'),
          ],
        ),
      );
    }
    if (vm.errorMessage != null && vm.forecast == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text(vm.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: vm.refresh,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    final forecast = vm.forecast;
    if (forecast == null) return const SizedBox.shrink();

    if (!forecast.hasData) {
      return _NoDataState(vm: vm, forecast: forecast);
    }

    final current = forecast.current;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current != null) ...[
            _CurrentMarine(hour: current),
            const SizedBox(height: 16),
          ],
          const Text(
            'Per 3 jam (3 hari)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...forecast.every3Hours.map(_MarineRow.new),
          const SizedBox(height: 8),
          _RegionSection(vm: vm),
          const SizedBox(height: 8),
          const _BmkgWebLink(
            url: AppConstants.bmkgWaveUrl,
            label: 'Prakiraan gelombang BMKG (web)',
          ),
          DataSourceFooter(
            source: 'Open-Meteo Marine',
            fetchedAt: forecast.fetchedAt,
            isStale: forecast.isStale,
            onRefresh: vm.refresh,
            refreshing: vm.loading,
          ),
        ],
      ),
    );
  }
}

/// Titik darat/sungai: Open-Meteo mengembalikan null semua.
/// Tampilkan pesan, JANGAN angka 0.
class _NoDataState extends StatelessWidget {
  const _NoDataState({required this.vm, required this.forecast});

  final MarineViewModel vm;
  final MarineForecast forecast;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.waves, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Tidak ada data gelombang untuk titik ini.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Titik ini kemungkinan di darat atau perairan yang tidak '
            'tercakup model gelombang. Geser peta ke laut terbuka lalu '
            'coba lagi.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _RegionSection(vm: vm),
          const SizedBox(height: 8),
          const _BmkgWebLink(
            url: AppConstants.bmkgWaveUrl,
            label: 'Prakiraan gelombang BMKG (web)',
          ),
          DataSourceFooter(
            source: 'Open-Meteo Marine',
            fetchedAt: forecast.fetchedAt,
            isStale: forecast.isStale,
            onRefresh: vm.refresh,
            refreshing: vm.loading,
          ),
        ],
      ),
    );
  }
}

class _CurrentMarine extends StatelessWidget {
  const _CurrentMarine({required this.hour, this.category});

  final MarineHour hour;

  /// Kategori gelombang resmi BMKG (mis. "Sedang") — ditampilkan bila
  /// diberikan (ramalan wilayah). Ramalan titik tidak memakainya.
  final String? category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                        'Saat ini (${IdFormat.timeHm(hour.time)} WIB)',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (category != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Chip(
                            label: Text('Kategori BMKG: $category'),
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
                if (hour.seaTempC != null)
                  Text(
                    '${hour.seaTempC!.toStringAsFixed(1)}°C air',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (hour.waveDirectionDeg != null)
                  _Fact(
                    label: 'Arah',
                    value:
                        '${hour.waveDirectionDeg!.toStringAsFixed(0)}° '
                        '(${NavMath.compassPointShort(hour.waveDirectionDeg!)})',
                  ),
                if (hour.wavePeriodS != null)
                  _Fact(
                    label: 'Periode',
                    value: '${hour.wavePeriodS!.toStringAsFixed(1)} dtk',
                  ),
                if (hour.swellHeightM != null)
                  _Fact(
                    label: 'Swell',
                    value:
                        '${hour.swellHeightM!.toStringAsFixed(1)} m'
                        '${hour.swellDirectionDeg != null ? ' · ${hour.swellDirectionDeg!.toStringAsFixed(0)}°' : ''}',
                  ),
                if (hour.currentKnots != null)
                  _Fact(
                    label: 'Arus',
                    value:
                        '${hour.currentKnots!.toStringAsFixed(1)} kt'
                        '${hour.currentDirectionDeg != null ? ' · ${hour.currentDirectionDeg!.toStringAsFixed(0)}°' : ''}',
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

class _MarineRow extends StatelessWidget {
  const _MarineRow(this.hour);

  final MarineHour hour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday = hour.time.day == now.day &&
        hour.time.month == now.month &&
        hour.time.year == now.year;
    final label = isToday
        ? IdFormat.timeHm(hour.time)
        : '${IdFormat.dateShort(hour.time)} ${IdFormat.timeHm(hour.time)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 76, child: Text(label)),
          Expanded(
            child: Text(
              hour.waveHeightM == null
                  ? '-'
                  : '${hour.waveHeightM!.toStringAsFixed(1)} m',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (hour.waveDirectionDeg != null)
            Text(
              '${hour.waveDirectionDeg!.toStringAsFixed(0)}° '
              '(${NavMath.compassPointShort(hour.waveDirectionDeg!)})',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(width: 8),
          if (hour.wavePeriodS != null)
            SizedBox(
              width: 56,
              child: Text(
                '${hour.wavePeriodS!.toStringAsFixed(1)} dtk',
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ramalan gelombang per wilayah laut (R-15, ronde 2).
/// User memilih satu wilayah dari [kSeaRegions] → ramalan Open-Meteo
/// Marine di TITIK TENGAH wilayah itu. UI menulis eksplisit bahwa ini
/// ramalan titik tengah, BUKAN rata-rata wilayah, beserta koordinat
/// titiknya. Ramalan titik posisi user di atas tidak tersentuh.
///
/// Ronde 2 fase 2: wilayah berkode BMKG (M.xx) JUGA memuat prakiraan
/// resmi BMKG untuk SELURUH wilayah perairan itu — tampil default
/// bila tersedia (sumber resmi), dengan pemilih sumber
/// "BMKG (resmi)" vs "Open-Meteo" bila kedua sumber ada datanya.
/// Bila BMKG gagal/kosong, panel jatuh ke Open-Meteo + catatan.
/// Wilayah tanpa kode BMKG (SCS/GOT/ANDA): Open-Meteo saja.
class _RegionSection extends StatelessWidget {
  const _RegionSection({required this.vm});

  final MarineViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final region = vm.selectedRegion;
    final regionForecast = vm.regionForecast;
    final regionCurrent = regionForecast?.current;
    final bmkgForecast = vm.bmkgRegionForecast;
    final showingBmkg =
        vm.regionSource == RegionWaveSource.bmkg && bmkgForecast != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
          'Gelombang per wilayah laut',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Pilih satu wilayah laut — prakiraan resmi BMKG bila '
          'tersedia, atau Open-Meteo Marine di titik tengah wilayah.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        DropdownButton<SeaRegion>(
          value: region,
          hint: const Text('Pilih wilayah laut…'),
          isExpanded: true,
          items: kSeaRegions
              .map(
                (r) => DropdownMenuItem<SeaRegion>(
                  value: r,
                  child: Text(
                    r.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (r) {
            if (r != null) vm.loadRegion(r);
          },
        ),
        if (region != null) ...[
          const SizedBox(height: 8),
          Text(
            'Titik tengah: '
            '${NavMath.formatDecimal(region.latitude, fractionDigits: 2)}, '
            '${NavMath.formatDecimal(region.longitude, fractionDigits: 2)}'
            '${region.bmkgCode != null ? ' • Kode BMKG ${region.bmkgCode}' : ' • di luar pembagian wilayah BMKG'}',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            showingBmkg
                ? 'Prakiraan resmi BMKG untuk wilayah perairan ini.'
                : 'Ramalan titik tengah wilayah — bukan rata-rata seluruh wilayah.',
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          if (vm.regionSourcePickerVisible)
            SegmentedButton<RegionWaveSource>(
              segments: const [
                ButtonSegment<RegionWaveSource>(
                  value: RegionWaveSource.bmkg,
                  label: Text('BMKG (resmi)'),
                ),
                ButtonSegment<RegionWaveSource>(
                  value: RegionWaveSource.openMeteo,
                  label: Text('Open-Meteo'),
                ),
              ],
              selected: {vm.regionSource},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  vm.setRegionSource(selection.first);
                }
              },
            ),
          if (vm.bmkgRegionErrorMessage != null &&
              bmkgForecast == null &&
              regionForecast != null)
            Text(
              'Prakiraan BMKG tidak tersedia saat ini — memakai '
              'Open-Meteo.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          if ((vm.regionLoading || vm.bmkgRegionLoading) &&
              regionForecast == null &&
              bmkgForecast == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Memuat ramalan wilayah…'),
                  ],
                ),
              ),
            ),
          // `showingBmkg` sudah menyiratkan `bmkgForecast != null`
          // (didefinisikan di atas sebagai `... && bmkgForecast != null`),
          // jadi analyzer mempromosikan tipenya tanpa pengulangan
          // (komentar lama yang mengulang cek null justru memicu
          // warning unnecessary_null_comparison — dihapus).
          if (showingBmkg) ...[
            BmkgForecastBody(forecast: bmkgForecast),
            DataSourceFooter(
              source: 'BMKG',
              fetchedAt: bmkgForecast.fetchedAt,
              isStale: bmkgForecast.isStale,
              onRefresh: vm.refreshRegion,
              refreshing: vm.regionLoading || vm.bmkgRegionLoading,
            ),
          ] else ...[
            if (vm.regionErrorMessage != null && regionForecast == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(vm.regionErrorMessage!,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: vm.refreshRegion,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            if (regionForecast != null) ...[
              if (!regionForecast.hasData)
                const Text(
                  'Tidak ada data gelombang untuk titik tengah wilayah ini.',
                ),
              if (regionCurrent != null) ...[
                _CurrentMarine(
                  hour: regionCurrent,
                  category: regionCurrent.waveHeightM == null
                      ? null
                      : bmkgWaveCategory(regionCurrent.waveHeightM!),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Per 3 jam (3 hari)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ...regionForecast.every3Hours.map(_MarineRow.new),
              ],
              DataSourceFooter(
                source: 'Open-Meteo Marine',
                fetchedAt: regionForecast.fetchedAt,
                isStale: regionForecast.isStale,
                onRefresh: vm.refreshRegion,
                refreshing: vm.regionLoading || vm.bmkgRegionLoading,
              ),
            ],
          ],
        ],
        const SizedBox(height: 8),
        const _BmkgWebLink(
          url: kBmkgMaritimUrl,
          label: 'Prakiraan resmi BMKG per wilayah (web)',
        ),
      ],
    );
  }
}

/// Tautan web BMKG (halaman resmi bmkg.go.id).
/// Bila browser tidak bisa dibuka, tampilkan URL-nya agar user bisa
/// membuka manual — jangan pernah gagal diam-diam (ronde 2, item 3).
class _BmkgWebLink extends StatelessWidget {
  const _BmkgWebLink({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(url);
    bool opened = false;
    try {
      // launchUrl langsung tanpa gate canLaunchUrl: canLaunchUrl bisa
      // false di perangkat tanpa browser default terdaftar, padahal
      // launchUrl sendiri masih bisa membuka chooser browser.
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tidak bisa membuka browser. Salin alamat ini dan buka manual:\n$url',
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
  }
}
