import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/result.dart';

/// Lokasi GPS: permission_handler untuk alur izin (termasuk
/// permanentlyDenied -> buka Pengaturan), geolocator untuk posisi.
/// Stream posisi: akurasi tinggi, update bila bergerak >= 10 m.
class LocationService {
  LocationService();

  StreamSubscription<Position>? _positionSubscription;

  /// Minta izin lokasi. Mengembalikan true bila diizinkan.
  /// Bila ditolak permanen, membuka Pengaturan aplikasi.
  Future<bool> requestPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      status = await Permission.locationWhenInUse.status;
      return status.isGranted;
    }
    final result = await Permission.locationWhenInUse.request();
    return result.isGranted;
  }

  Future<bool> get hasPermission async =>
      (await Permission.locationWhenInUse.status).isGranted;

  Future<bool> get isLocationServiceEnabled async =>
      Geolocator.isLocationServiceEnabled();

  Future<Result<Position>> getCurrentPosition() async {
    if (!await isLocationServiceEnabled) {
      return Result.error(
        Exception('Layanan lokasi (GPS) belum aktif di perangkat.'),
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 20));
      return Result.ok(position);
    } on TimeoutException {
      return Result.error(
        Exception('GPS lambat mendapatkan posisi. Coba lagi.'),
      );
    } catch (e) {
      return Result.error(Exception('Gagal mendapatkan posisi: $e'));
    }
  }

  /// Stream posisi berkelanjutan (untuk mode ikuti + panah kapal).
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  /// Mulai mendengarkan stream; simpan subscription untuk dibatalkan.
  void listenToPositionStream(void Function(Position) onPosition) {
    _positionSubscription?.cancel();
    _positionSubscription = positionStream().listen(
      onPosition,
      onError: (_) {
        // Stream error diabaikan; posisi terakhir tetap dipakai.
      },
    );
  }

  void stopPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void dispose() => stopPositionStream();
}
