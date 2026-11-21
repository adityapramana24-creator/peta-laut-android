import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/waypoint.dart';
import '../../../domain/models/windy.dart';
import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/result.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../view_models/windy_viewmodel.dart';

/// Cuaca di sepanjang rute: prakiraan di tiap waypoint pada jam
/// ETA-nya (dari posisi sendiri sekarang, atau dari titik pertama).
Future<void> showRouteWeatherSheet(
  BuildContext context, {
  RoutePlan? initialRoute,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RouteWeatherSheet(initialRoute: initialRoute),
  );
}

class RouteWeatherSheet extends StatefulWidget {
  const RouteWeatherSheet({super.key, this.initialRoute});

  final RoutePlan? initialRoute;

  @override
  State<RouteWeatherSheet> createState() => _RouteWeatherSheetState();
}

class _RouteWeatherSheetState extends State<RouteWeatherSheet> {
  RoutePlan? _route;
  List<RouteWeatherPoint>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
  }

  Future<void> _load() async {
    final route = _route;
    if (route == null) return;
    final nav = context.read<NavigationViewModel>();
    final windy = context.read<WindyViewModel>();
    final wps = nav.routeWaypoints(route);
    if (wps.length < 2) {
      setState(() {
        _error = 'Rute ini hanya punya ${wps.length} titik aktif.';
        _results = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    // ETA per waypoint: mulai dari posisi sendiri (bila ada),
    // else dari titik pertama pada jam ini.
    final own = nav.ownPosition;
    final points = <({String name, double lat, double lon, DateTime eta})>[];
    var now = DateTime.now();
    var prevLat = own?.latitude ?? wps.first.latitude;
    var prevLon = own?.longitude ?? wps.first.longitude;
    for (final wp in wps) {
      final legM = NavMath.distanceMeters(
        prevLat,
        prevLon,
        wp.latitude,
        wp.longitude,
      );
      final legEta = NavMath.etaDuration(legM, route.speedKnots);
      now = now.add(legEta ?? Duration.zero);
      points.add((name: wp.name, lat: wp.latitude, lon: wp.longitude, eta: now));
      prevLat = wp.latitude;
      prevLon = wp.longitude;
    }
    final result = await windy.routeWeather(points);
    if (!mounted) return;
    switch (result) {
      case Ok(value: final list):
        setState(() {
          _results = list;
          _loading = false;
        });
      case Error(error: final error):
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final routes = nav.routes;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
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
            const Text(
              'Cuaca di rute',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              'Prakiraan di tiap titik rute pada jam perkiraan tiba.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              nav.ownPosition == null
                  ? 'Berangkat dari titik pertama (GPS belum tersedia).'
                  : 'Berangkat dari posisi saya sekarang.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (routes.isEmpty)
              const Text(
                'Belum ada rute. Buat rute dulu dari menu Titik & Rute.',
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<RoutePlan>(
                      // Rute bisa terhapus saat lembar terbuka — nilai
                      // yang tidak ada di daftar akan membuat dropdown
                      // error, jadi amankan dengan contains.
                      initialValue:
                          _route != null && routes.contains(_route)
                              ? _route
                              : null,
                      decoration: const InputDecoration(
                        labelText: 'Rute',
                        border: OutlineInputBorder(),
                      ),
                      items: routes.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r.name),
                        );
                      }).toList(),
                      onChanged: (r) => setState(() {
                        _route = r;
                        _results = null;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _route == null || _loading ? null : _load,
                    icon: const Icon(Icons.cloud),
                    label: const Text('Muat'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
              )
            else if (_results != null)
              Expanded(
                child: ListView.builder(
                  itemCount: _results!.length,
                  itemBuilder: (context, index) {
                    final p = _results![index];
                    return _RouteWeatherTile(point: p);
                  },
                ),
              )
            else
              Text(
                'Pilih rute lalu tekan Muat.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteWeatherTile extends StatelessWidget {
  const _RouteWeatherTile({required this.point});

  final RouteWeatherPoint point;

  @override
  Widget build(BuildContext context) {
    final wind = point.windKnots == null
        ? '—'
        : '${point.windKnots!.toStringAsFixed(0)} kt'
            '${point.windDirDeg == null ? '' : ' ${NavMath.compassPointShort(point.windDirDeg!)}'}';
    final gust = point.gustsKnots == null
        ? ''
        : ' (hemb ${point.gustsKnots!.toStringAsFixed(0)} kt)';
    final wave = point.waveHeightM == null
        ? '—'
        : '${point.waveHeightM!.toStringAsFixed(1)} m';
    final rain = point.rainMm == null
        ? '—'
        : '${point.rainMm!.toStringAsFixed(1)} mm';
    final temp = point.tempC == null
        ? '—'
        : '${point.tempC!.toStringAsFixed(0)}°C';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.place),
        title: Text(point.waypointName),
        subtitle: Text(
          'Tiba ${IdFormat.dateTimeShort(point.eta)} WIB\n'
          'Angin $wind$gust · Gelombang $wave · '
          'Hujan $rain · $temp',
        ),
        isThreeLine: true,
      ),
    );
  }
}
