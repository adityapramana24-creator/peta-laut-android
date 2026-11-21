import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/port.dart';
import '../../../domain/models/weather.dart';
import '../../../utils/formatters.dart';
import '../../core/widgets/data_source_footer.dart';
import '../view_models/weather_viewmodel.dart';

/// Panel Cuaca (R-14): BMKG 3 hari per pelabuhan terdekat (bisa diganti).
Future<void> showWeatherPanel(
  BuildContext context, {
  required LatLng point,
  required WeatherViewModel viewModel,
}) {
  viewModel.loadForPoint(point);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<WeatherViewModel>.value(
      value: viewModel,
      child: const WeatherPanel(),
    ),
  ).then((_) => viewModel.dispose());
}

class WeatherPanel extends StatelessWidget {
  const WeatherPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WeatherViewModel>();
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
                Icon(Icons.cloud, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Cuaca',
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
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Pelabuhan: '),
                const SizedBox(width: 4),
                Expanded(
                  child: DropdownButton<Port>(
                    value: vm.port,
                    isExpanded: true,
                    items: vm.ports.map((port) {
                      return DropdownMenuItem<Port>(
                        value: port,
                        child: Text(port.name),
                      );
                    }).toList(),
                    onChanged: (port) {
                      if (port != null) vm.selectPort(port);
                    },
                  ),
                ),
              ],
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

  final WeatherViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.loading && vm.forecast == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Memuat prakiraan BMKG…'),
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

    final current = forecast.current;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (forecast.locationName.isNotEmpty)
            Text(
              forecast.locationName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          if (current != null) ...[
            const SizedBox(height: 8),
            _CurrentSlot(slot: current),
            const SizedBox(height: 16),
          ],
          ...forecast.days.map((day) {
            final dayDate = day.first.localTime;
            return _DaySection(
              title: IdFormat.dayDateLong(dayDate),
              slots: day,
            );
          }),
          DataSourceFooter(
            source: 'BMKG'
                '${forecast.analysisDate != null ? ' · analisis ${IdFormat.dateTimeShort(forecast.analysisDate!)}' : ''}',
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

class _CurrentSlot extends StatelessWidget {
  const _CurrentSlot({required this.slot});

  final BmkgSlot slot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              conditionIcon(slot.condition),
              size: 44,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slot.tempC != null)
                    Text(
                      '${slot.tempC!.toStringAsFixed(0)}°C',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    slot.condition ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Saat ini (${IdFormat.timeHm(slot.localTime)})',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (slot.windKmh != null)
                  _MiniStat(
                    icon: Icons.air,
                    text:
                        '${slot.windKmh!.toStringAsFixed(0)} km/j · '
                        '${slot.windKnots!.toStringAsFixed(0)} kt',
                  ),
                if (slot.windFrom != null)
                  _MiniStat(
                    icon: Icons.navigation,
                    text: 'dari ${slot.windFrom!}',
                  ),
                if (slot.humidity != null)
                  _MiniStat(
                    icon: Icons.water_drop,
                    text: '${slot.humidity}% lembap',
                  ),
                if (slot.rainMm != null && slot.rainMm! > 0)
                  _MiniStat(
                    icon: Icons.umbrella,
                    text: '${slot.rainMm} mm hujan',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.title, required this.slots});

  final String title;
  final List<BmkgSlot> slots;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...slots.map((slot) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(IdFormat.timeHm(slot.localTime)),
                ),
                Icon(
                  conditionIcon(slot.condition),
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slot.condition ?? '-',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (slot.tempC != null)
                  Text('${slot.tempC!.toStringAsFixed(0)}°C'),
                const SizedBox(width: 8),
                if (slot.windKmh != null)
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${slot.windKnots!.toStringAsFixed(0)} kt',
                      textAlign: TextAlign.right,
                    ),
                  ),
                if (slot.rainMm != null && slot.rainMm! > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '${slot.rainMm} mm',
                      style: TextStyle(color: scheme.primary),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Ikon kondisi dari weather_desc BMKG (pencocokan substring).
IconData conditionIcon(String? condition) {
  final c = (condition ?? '').toLowerCase();
  if (c.contains('petir')) return Icons.thunderstorm;
  if (c.contains('hujan lebat')) return Icons.thunderstorm;
  if (c.contains('hujan')) return Icons.rainy;
  if (c.contains('kabut')) return Icons.foggy;
  if (c.contains('tebal')) return Icons.wb_cloudy;
  if (c.contains('berawan')) return Icons.partly_cloudy_day;
  if (c.contains('cerah')) return Icons.wb_sunny;
  return Icons.cloud;
}
