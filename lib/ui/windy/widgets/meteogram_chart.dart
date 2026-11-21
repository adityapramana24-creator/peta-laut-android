import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/marine.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';

/// Meteogram dari PointForecast: grafik angin + hembusan (knot)
/// dan tinggi gelombang (m), plus tabel per 3 jam di bawahnya.
/// Waktu dalam WIB (zona acuan aplikasi).
class MeteogramChart extends StatelessWidget {
  const MeteogramChart({super.key, required this.forecast});

  final PointForecast forecast;

  @override
  Widget build(BuildContext context) {
    final hours = forecast.forecast;
    if (hours.length < 2) {
      return const Text('Data prakiraan belum cukup untuk grafik.');
    }
    final start = hours.first.time;
    final maxX = hours.last.time.difference(start).inMinutes / 60.0;
    final nowX = DateTime.now().difference(start).inMinutes / 60.0;

    String timeLabel(double x) {
      final t = start.add(Duration(minutes: (x * 60).round()));
      return IdFormat.timeHm(t);
    }

    final windSpots = <FlSpot>[];
    final gustSpots = <FlSpot>[];
    for (final h in hours) {
      final x = h.time.difference(start).inMinutes / 60.0;
      if (h.windKnots != null) windSpots.add(FlSpot(x, h.windKnots!));
      if (h.gustsKmh != null) {
        gustSpots.add(FlSpot(x, NavMath.kmhToKnots(h.gustsKmh!)));
      }
    }
    final waveSpots = <FlSpot>[];
    for (final m in forecast.marine) {
      if (m.waveHeightM == null) continue;
      final x = m.time.difference(start).inMinutes / 60.0;
      if (x >= 0) waveSpots.add(FlSpot(x, m.waveHeightM!));
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartTitle(
          title: 'Angin (knot)',
          legend: [
            _LegendDot(color: scheme.primary, label: 'Angin'),
            _LegendDot(color: scheme.error, label: 'Hembusan'),
          ],
        ),
        SizedBox(
          height: 140,
          child: windSpots.length < 2 && gustSpots.length < 2
              ? const Text(
                  'Tidak ada data angin di titik ini.',
                  style: TextStyle(fontSize: 12),
                )
              : _LineChart(
                  maxX: maxX,
                  nowX: nowX,
                  timeLabel: timeLabel,
                  bars: [
                    if (windSpots.length >= 2)
                      LineChartBarData(
                        spots: windSpots,
                        isCurved: true,
                        color: scheme.primary,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                      ),
                    if (gustSpots.length >= 2)
                      LineChartBarData(
                        spots: gustSpots,
                        isCurved: true,
                        color: scheme.error,
                        barWidth: 1.5,
                        dotData: const FlDotData(show: false),
                      ),
                  ],
                  yInterval: 5,
                ),
        ),
        const SizedBox(height: 12),
        const _ChartTitle(title: 'Tinggi gelombang (m)', legend: []),
        if (waveSpots.length < 2)
          const Text(
            'Tidak ada data gelombang di titik ini (mungkin darat).',
            style: TextStyle(fontSize: 12),
          )
        else
          SizedBox(
            height: 120,
            child: _LineChart(
              maxX: maxX,
              nowX: nowX,
              timeLabel: timeLabel,
              bars: [
                LineChartBarData(
                  spots: waveSpots,
                  isCurved: true,
                  color: Colors.teal,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.teal.withValues(alpha: 0.15),
                  ),
                ),
              ],
              yInterval: 0.5,
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Per 3 jam',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ..._detailRows(),
      ],
    );
  }

  List<Widget> _detailRows() {
    final rows = <Widget>[];
    final hours = forecast.forecast;
    final marineByHour = <int, MarineHour>{};
    for (final m in forecast.marine) {
      marineByHour[m.time.millisecondsSinceEpoch] = m;
    }
    for (var i = 0; i < hours.length; i += 3) {
      final h = hours[i];
      final m = marineByHour[h.time.millisecondsSinceEpoch];
      final wind = h.windKnots == null
          ? '—'
          : '${h.windKnots!.toStringAsFixed(0)} kt'
              '${h.windDirDeg == null ? '' : ' ${NavMath.compassPointShort(h.windDirDeg!)}'}';
      final gust = h.gustsKmh == null
          ? ''
          : ' (hemb ${NavMath.kmhToKnots(h.gustsKmh!).toStringAsFixed(0)} kt)';
      final rain = h.precipitationMm == null
          ? '—'
          : '${h.precipitationMm!.toStringAsFixed(1)} mm';
      final wave = m?.waveHeightM == null
          ? '—'
          : '${m!.waveHeightM!.toStringAsFixed(1)} m';
      final temp =
          h.tempC == null ? '—' : '${h.tempC!.toStringAsFixed(0)}°C';
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  '${IdFormat.dateShort(h.time)} ${IdFormat.timeHm(h.time)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(
                  'Angin $wind$gust · Gelombang $wave · '
                  'Hujan $rain · $temp',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle({required this.title, required this.legend});

  final String title;
  final List<Widget> legend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ...legend.map(
            (w) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: w,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.maxX,
    required this.nowX,
    required this.timeLabel,
    required this.bars,
    required this.yInterval,
  });

  final double maxX;
  final double nowX;
  final String Function(double) timeLabel;
  final List<LineChartBarData> bars;
  final double yInterval;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          horizontalInterval: yInterval,
          verticalInterval: 12,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: yInterval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(yInterval < 1 ? 1 : 0),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 12,
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
              ),
          ],
        ),
      ),
    );
  }
}
