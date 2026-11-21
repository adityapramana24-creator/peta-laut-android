import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/tide.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../core/widgets/data_source_footer.dart';
import '../view_models/tides_viewmodel.dart';

/// Panel Pasang Surut (R-13): ekstremum hari ini + besok WIB + kurva 48 jam.
Future<void> showTidesPanel(
  BuildContext context, {
  required LatLng point,
  required TidesViewModel viewModel,
}) {
  viewModel.load(point);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<TidesViewModel>.value(
      value: viewModel,
      child: const TidesPanel(),
    ),
  ).then((_) => viewModel.dispose());
}

class TidesPanel extends StatelessWidget {
  const TidesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TidesViewModel>();
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
                const Text(
                  'Pasang Surut',
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

  final TidesViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.loading && vm.forecast == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Menghitung pasang surut…'),
            Text(
              'Model harmonik — bisa sampai ~20 detik.',
              style: TextStyle(fontSize: 12),
            ),
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

    final nowWib = IdFormat.toWib(DateTime.now().toUtc());
    final tomorrowWib = nowWib.add(const Duration(days: 1));
    final today = forecast.extremaForDay(nowWib);
    final tomorrow = forecast.extremaForDay(tomorrowWib);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DaySection(
            title: 'Hari ini — ${IdFormat.dayDateLong(nowWib)}',
            extrema: today,
          ),
          const SizedBox(height: 12),
          _DaySection(
            title: 'Besok — ${IdFormat.dayDateLong(tomorrowWib)}',
            extrema: tomorrow,
          ),
          const SizedBox(height: 16),
          const Text(
            'Kurva 48 jam',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: _TideChart(forecast: forecast),
          ),
          DataSourceFooter(
            source: 'hamandmore — prediksi model harmonik global, '
                'bukan gauge lokal',
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

class _DaySection extends StatelessWidget {
  const _DaySection({required this.title, required this.extrema});

  final String title;
  final List<TideExtremum> extrema;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (extrema.isEmpty)
          Text(
            'Tidak ada ekstremum tercatat hari ini.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          ...extrema.map((e) {
            final time = IdFormat.timeHm(e.timeWib);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    e.isHigh
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 18,
                    color: e.isHigh
                        ? scheme.primary
                        : scheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    e.isHigh ? 'Pasang' : 'Surut',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  Text('$time WIB'),
                  const Spacer(),
                  Text(
                    '${e.heightM.toStringAsFixed(2)} m',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _TideChart extends StatelessWidget {
  const _TideChart({required this.forecast});

  final TideForecast forecast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final curve = forecast.curveOrInterpolated;
    if (curve.length < 2) {
      return const Center(child: Text('Kurva tidak tersedia.'));
    }
    final start = curve.first.timeUtc;
    final spots = curve.map((p) {
      final x = p.timeUtc.difference(start).inMinutes / 60.0;
      return FlSpot(x, p.heightM);
    }).toList();
    final heights = curve.map((p) => p.heightM);
    final minY = heights.reduce((a, b) => a < b ? a : b) - 0.3;
    final maxY = heights.reduce((a, b) => a > b ? a : b) + 0.3;
    final maxX = curve.last.timeUtc.difference(start).inMinutes / 60.0;
    final nowX = DateTime.now()
            .toUtc()
            .difference(start)
            .inMinutes /
        60.0;
    final startWib = IdFormat.toWib(start);

    String timeLabel(double hours) {
      final t = startWib.add(Duration(minutes: (hours * 60).round()));
      return IdFormat.timeHm(t);
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: scheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
        gridData: const FlGridData(
          show: true,
          horizontalInterval: 0.5,
          verticalInterval: 6,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 0.5,
              getTitlesWidget: (value, meta) => Text(
                '${value.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 6,
              getTitlesWidget: (value, meta) => Text(
                timeLabel(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            if (nowX >= 0 && nowX <= maxX)
              VerticalLine(
                x: nowX,
                color: scheme.error,
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
          ],
        ),
        borderData: FlBorderData(show: true),
      ),
    );
  }
}
