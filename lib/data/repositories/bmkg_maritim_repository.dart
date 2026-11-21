import 'dart:convert';

import '../../domain/models/bmkg_maritim.dart';
import '../../utils/result.dart';
import '../local/app_database.dart';
import '../services/bmkg_maritim_service.dart';

/// Prakiraan maritim BMKG per wilayah (kode M.xx), cache per wilayah.
///
/// POLA CACHE: sama seperti MarineRepository — tabel cache Drift
/// ([AppDatabase.getCached]/[putCached]), BUKAN SharedPreferences
/// (payload prakiraan ~40 entri/jam terlalu besar untuk prefs dan
/// pola cache app ini memang Drift).
///
/// - TTL cache segar: 3 jam. ALASAN: BMKG menerbitkan prakiraan baru
///   ~1x/hari (setelah siklus prakiraan maritim ~00 UTC); refresh
///   tiap 3 jam sudah lebih dari cukup dan hemat kuota kapal.
///   Jangan polling tiap menit.
/// - Gagal fetch + ada cache (segar atau basi): kembalikan cache
///   dengan [BmkgMaritimForecast.isStale] true — data terakhir
///   TETAP TAMPIL saat offline. UI melabeli kebasihan dari
///   [BmkgMaritimForecast.fetchedAt] + jendela berlaku
///   (valid_from/valid_to); data lewat valid_to DILABELI
///   kedaluwarsa, tidak ditampilkan seolah berlaku.
/// - [getCachedForecast] membaca cache SAJA (tanpa jaringan) —
///   untuk melukis marker peta langsung saat app dibuka.
class BmkgMaritimRepository {
  BmkgMaritimRepository({required AppDatabase db, BmkgMaritimService? service})
      : _db = db,
        _service = service ?? BmkgMaritimService();

  final AppDatabase _db;
  final BmkgMaritimService _service;

  static const _ttl = Duration(hours: 3);
  static const _scope = 'bmkg_maritim';

  String _key(String code) => 'bmkg_maritim|$code';

  Future<Result<BmkgMaritimForecast>> getForecast(
    String code, {
    bool forceRefresh = false,
  }) async {
    final key = _key(code);
    if (!forceRefresh) {
      final cached = await _readCache(key);
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) < _ttl) {
        return Result.ok(cached);
      }
    }
    final result = await _service.fetchForecast(code);
    switch (result) {
      case Ok(value: final forecast):
        await _writeCache(key, forecast);
        return Result.ok(forecast);
      case Error(error: final error):
        final cached = await _readCache(key);
        if (cached != null) {
          return Result.ok(cached.copyWith(isStale: true));
        }
        return Result.error(error);
    }
  }

  /// Cache saja, tanpa jaringan. null bila belum pernah di-fetch.
  Future<BmkgMaritimForecast?> getCachedForecast(String code) =>
      _readCache(_key(code));

  Future<BmkgMaritimForecast?> _readCache(String key) async {
    final cached = await _db.getCached(key);
    if (cached == null) return null;
    try {
      final decoded = jsonDecode(cached.payload);
      if (decoded is! Map<String, dynamic>) return null;
      return BmkgMaritimForecast.fromCacheJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    String key,
    BmkgMaritimForecast forecast,
  ) async {
    try {
      await _db.putCached(
        key: key,
        scope: _scope,
        payload: jsonEncode(forecast.toJson()),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai.
    }
  }
}
