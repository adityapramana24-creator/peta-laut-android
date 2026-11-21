import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../domain/models/marine.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../core/widgets/data_source_footer.dart';
import '../view_models/marine_viewmodel.dart';

/// Panel Gelombang (R-15): Open-Meteo Marine 3 hari + arus/swell/SST.
/// Titik darat -> pesan "tidak ada data", BUKAN 0.
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
          _BmkgWaveLink(),
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
          _BmkgWaveLink(),
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
  const _CurrentMarine({required this.hour});

  final MarineHour hour;

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

/// Tautan prakiraan gelombang BMKG (BMKG tidak punya API gelombang).
class _BmkgWaveLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Prakiraan gelombang BMKG (web)'),
      onPressed: () async {
        final uri = Uri.parse(AppConstants.bmkgWaveUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
