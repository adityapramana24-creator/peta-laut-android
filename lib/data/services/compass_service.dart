import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Kompas magnetik perangkat (flutter_compass 0.8.1).
/// Diisolasi di balik service ini: bila plugin bermasalah di device
/// tertentu, MapViewModel jatuh ke heading GPS (course saat bergerak).
/// Nilai null = tidak ada sensor / belum ada data.
class CompassService {
  CompassService();

  final ValueNotifier<double?> headingNotifier = ValueNotifier(null);
  StreamSubscription<CompassEvent>? _subscription;
  bool _started = false;

  /// Mulai mendengarkan sensor kompas (sekali saja).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final events = FlutterCompass.events;
      if (events == null) return;
      _subscription = events.listen(
        (event) {
          final heading = event.heading;
          if (heading != null) headingNotifier.value = heading;
        },
        onError: (_) {
          // Sensor gagal — heading tetap null, fallback GPS dipakai.
        },
      );
    } catch (_) {
      // Plugin tidak tersedia di device ini — fallback GPS.
    }
  }

  double? get heading => headingNotifier.value;

  void dispose() {
    _subscription?.cancel();
    headingNotifier.dispose();
  }
}
