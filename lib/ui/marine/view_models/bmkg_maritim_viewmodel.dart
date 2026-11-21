import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../config/sea_regions.dart';
import '../../../data/repositories/bmkg_maritim_repository.dart';
import '../../../domain/models/bmkg_maritim.dart';
import '../../../utils/result.dart';

/// Loader prakiraan gelombang BMKG untuk MARKER PETA (ronde 2, fase 2).
///
/// Memuat prakiraan ke-20 wilayah berkode BMKG (M.xx) dari
/// [kSeaRegions] — 3 wilayah non-BMKG (SCS/GOT/ANDA, bmkgCode null)
/// TIDAK dimuat (tidak ada endpoint BMKG-nya; tetap Open-Meteo di
/// panel). Widget BmkgWaveMarkers membaca [forecasts] dari sini.
///
/// REFRESH OTOMATIS (tanpa polling tiap menit):
/// - muat awal saat viewmodel dibuat (cache dulu, lalu jaringan);
/// - timer tiap 3 jam saat app terbuka;
/// - saat app kembali dari background (resume), bila refresh terakhir
///   sudah >3 jam lalu.
/// ALASAN 3 jam: BMKG menerbitkan prakiraan baru ~1x/hari (setelah
/// siklus prakiraan maritim ~00 UTC); refresh lebih sering hanya
/// membuang baterai + kuota kapal tanpa data baru.
///
/// Hemat koneksi kapal: fetch jaringan per batch 5 wilayah paralel
/// (bukan 20 sekaligus); tiap wilayah yang gagal fetch tetap memakai
/// cache-nya (repository) — satu wilayah gagal tidak menggagalkan
/// 19 lainnya.
class BmkgMaritimViewModel extends ChangeNotifier
    with WidgetsBindingObserver {
  BmkgMaritimViewModel({required BmkgMaritimRepository repository})
      : _repository = repository {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(refreshInterval, (_) => refreshAll());
    // Muat awal lewat microtask agar notifyListeners pertama tidak
    // berjalan di tengah build (viewmodel dibuat lewat Provider).
    Future.microtask(loadAll);
  }

  /// Jeda refresh otomatis — lihat alasan di komentar class.
  static const Duration refreshInterval = Duration(hours: 3);

  /// Jumlah wilayah yang di-fetch paralel per batch.
  static const int batchSize = 5;

  final BmkgMaritimRepository _repository;
  final Map<String, BmkgMaritimForecast> _forecasts = {};
  Timer? _timer;
  DateTime? _lastRefreshUtc;
  bool _loading = false;
  bool _disposed = false;

  /// Prakiraan per wilayah, kunci = [SeaRegion.id] (kode M.xx).
  Map<String, BmkgMaritimForecast> get forecasts =>
      Map.unmodifiable(_forecasts);

  bool get loading => _loading;
  bool get hasAny => _forecasts.isNotEmpty;

  /// 20 wilayah berkode BMKG (M.xx) — hanya ini yang punya endpoint.
  static List<SeaRegion> get bmkgRegions => kSeaRegions
      .where((r) => r.bmkgCode != null)
      .toList(growable: false);

  /// Muat semua wilayah: cache dulu (peta langsung terisi, offline),
  /// lalu refresh jaringan per batch. Aman dipanggil berulang —
  /// panggilan bersamaan diabaikan.
  Future<void> loadAll({bool forceRefresh = false}) async {
    if (_loading || _disposed) return;
    _loading = true;
    _safeNotify();
    try {
      if (!forceRefresh) {
        for (final region in bmkgRegions) {
          final cached = await _repository.getCachedForecast(
            region.bmkgCode!,
          );
          if (cached != null) _forecasts[region.id] = cached;
        }
        if (_forecasts.isNotEmpty) _safeNotify();
      }
      final regions = bmkgRegions;
      for (var i = 0; i < regions.length; i += batchSize) {
        final batch = regions.skip(i).take(batchSize).toList();
        final results = await Future.wait(
          batch.map(
            (r) => _repository.getForecast(
              r.bmkgCode!,
              forceRefresh: forceRefresh,
            ),
          ),
        );
        var changed = false;
        for (var j = 0; j < batch.length; j++) {
          final result = results[j];
          if (result is Ok<BmkgMaritimForecast>) {
            _forecasts[batch[j].id] = result.value;
            changed = true;
          }
          // Error per wilayah: cache-nya (bila ada) sudah dipakai
          // repository sebagai stale; tanpa cache, wilayah itu
          // tidak bermarker — jangan tampilkan angka karangan.
        }
        if (changed) _safeNotify();
      }
      _lastRefreshUtc = DateTime.now().toUtc();
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Muat ulang paksa dari jaringan (tombol refresh manual / timer /
  /// resume). Cache tetap jadi fallback per wilayah bila fetch gagal.
  Future<void> refreshAll() => loadAll(forceRefresh: true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastRefreshUtc;
    if (last == null ||
        DateTime.now().toUtc().difference(last) >= refreshInterval) {
      refreshAll();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
