import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/sea_regions.dart';
import '../../../data/repositories/bmkg_maritim_repository.dart';
import '../../../data/repositories/marine_repository.dart';
import '../../../domain/models/bmkg_maritim.dart';
import '../../../domain/models/marine.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Sumber ramalan gelombang wilayah yang tampil di panel.
/// Default otomatis: BMKG bila tersedia, Open-Meteo bila BMKG
/// gagal/kosong (atau wilayah tanpa kode BMKG). User bisa mengubah
/// lewat pemilih sumber di seksi wilayah.
enum RegionWaveSource { bmkg, openMeteo }

/// ViewModel panel Gelombang (R-15): Open-Meteo Marine 3 hari.
/// Titik darat -> hasData false -> UI menampilkan "tidak ada data",
/// BUKAN 0.
///
/// Ronde 2: DITAMBAH ramalan per wilayah laut ([SeaRegion]) — state +
/// command TERPISAH dari ramalan titik posisi user. Perilaku titik
/// TIDAK berubah: [load]/[refresh]/[forecast]/[point] sama seperti
/// sebelumnya; wilayah dimuat lewat [loadRegion] dengan lat/lon titik
/// tengah wilayah, memakai repository + cache yang sama.
///
/// Ronde 2 fase 2: wilayah berkode BMKG (M.xx) JUGA memuat prakiraan
/// resmi BMKG ([BmkgMaritimRepository]) — sumber RESMI yang tampil
/// default bila tersedia, dengan Open-Meteo sebagai fallback.
/// [bmkgRepository] opsional agar konstruksi lama tetap kompilasi;
/// tanpa itu, panel berperilaku seperti ronde 2 awal (Open-Meteo
/// saja). Ramalan titik posisi user tetap Open-Meteo, tidak berubah.
class MarineViewModel extends ChangeNotifier {
  MarineViewModel({
    required MarineRepository repository,
    BmkgMaritimRepository? bmkgRepository,
  })  : _repository = repository,
        _bmkgRepository = bmkgRepository {
    loadCommand = Command1(_load);
    loadCommand.addListener(_onLoadChanged);
    regionLoadCommand = Command1(_loadRegion);
    regionLoadCommand.addListener(_onRegionLoadChanged);
    bmkgRegionLoadCommand = Command1(_loadBmkgRegion);
    bmkgRegionLoadCommand.addListener(_onBmkgRegionLoadChanged);
  }

  final MarineRepository _repository;
  final BmkgMaritimRepository? _bmkgRepository;
  late final Command1<MarineForecast, (LatLng, bool)> loadCommand;
  late final Command1<MarineForecast, (LatLng, bool)> regionLoadCommand;
  late final Command1<BmkgMaritimForecast, (String, bool)>
      bmkgRegionLoadCommand;

  MarineForecast? _forecast;
  LatLng? _point;
  String? _errorMessage;

  SeaRegion? _selectedRegion;
  MarineForecast? _regionForecast;
  String? _regionErrorMessage;

  BmkgMaritimForecast? _bmkgRegionForecast;
  String? _bmkgRegionErrorMessage;

  /// Pilihan sumber manual user; null = otomatis (BMKG bila ada).
  RegionWaveSource? _regionSourceOverride;

  MarineForecast? get forecast => _forecast;
  LatLng? get point => _point;
  String? get errorMessage => _errorMessage;
  bool get loading => loadCommand.running;

  SeaRegion? get selectedRegion => _selectedRegion;
  MarineForecast? get regionForecast => _regionForecast;
  String? get regionErrorMessage => _regionErrorMessage;
  bool get regionLoading => regionLoadCommand.running;

  BmkgMaritimForecast? get bmkgRegionForecast => _bmkgRegionForecast;
  String? get bmkgRegionErrorMessage => _bmkgRegionErrorMessage;
  bool get bmkgRegionLoading => bmkgRegionLoadCommand.running;
  bool get hasBmkgRepository => _bmkgRepository != null;

  /// Sumber yang tampil: pilihan manual user, atau otomatis —
  /// BMKG bila prakiraannya ada, Open-Meteo bila tidak.
  RegionWaveSource get regionSource {
    final override = _regionSourceOverride;
    if (override != null) return override;
    if (_bmkgRegionForecast != null) return RegionWaveSource.bmkg;
    return RegionWaveSource.openMeteo;
  }

  /// True bila pemilih sumber layak tampil (kedua sumber ada datanya).
  bool get regionSourcePickerVisible =>
      _bmkgRegionForecast != null && _regionForecast != null;

  void setRegionSource(RegionWaveSource source) {
    _regionSourceOverride = source;
    notifyListeners();
  }

  Future<Result<MarineForecast>> _load((LatLng, bool) args) async {
    final (point, forceRefresh) = args;
    _point = point;
    return _repository.getMarine(
      latitude: point.latitude,
      longitude: point.longitude,
      forceRefresh: forceRefresh,
    );
  }

  /// Sama seperti [_load] tapi TIDAK menyentuh [_point] — ramalan
  /// wilayah tidak boleh menggeser titik posisi user.
  Future<Result<MarineForecast>> _loadRegion((LatLng, bool) args) async {
    final (point, forceRefresh) = args;
    return _repository.getMarine(
      latitude: point.latitude,
      longitude: point.longitude,
      forceRefresh: forceRefresh,
    );
  }

  /// Prakiraan resmi BMKG untuk satu kode wilayah (M.xx).
  Future<Result<BmkgMaritimForecast>> _loadBmkgRegion(
    (String, bool) args,
  ) async {
    final (code, forceRefresh) = args;
    final repo = _bmkgRepository;
    if (repo == null) {
      return Result.error(Exception('Repository BMKG tidak tersedia.'));
    }
    return repo.getForecast(code, forceRefresh: forceRefresh);
  }

  void _onLoadChanged() {
    final result = loadCommand.result;
    if (result is Ok<MarineForecast>) {
      _forecast = result.value;
      _errorMessage = null;
    } else if (result is Error<MarineForecast>) {
      _errorMessage =
          result.error.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  void _onRegionLoadChanged() {
    final result = regionLoadCommand.result;
    if (result is Ok<MarineForecast>) {
      // Hasil BASI: fetch ini untuk wilayah lain — user ganti
      // wilayah saat fetch berjalan, dan execute wilayah baru
      // ditolak command karena masih running. Buang hasil ini
      // (jangan tampilkan ramalan wilayah A di bawah nama wilayah B)
      // lalu muat ulang wilayah yang sedang dipilih.
      final region = _selectedRegion;
      if (region == null ||
          result.value.latitude != region.latitude ||
          result.value.longitude != region.longitude) {
        if (region != null) loadRegion(region);
        return;
      }
      _regionForecast = result.value;
      _regionErrorMessage = null;
    } else if (result is Error<MarineForecast>) {
      _regionErrorMessage =
          result.error.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  void _onBmkgRegionLoadChanged() {
    final result = bmkgRegionLoadCommand.result;
    if (result is Ok<BmkgMaritimForecast>) {
      // Penjaga basi yang sama (lihat [_onRegionLoadChanged]):
      // kode wilayah hasil harus cocok dengan wilayah terpilih.
      final region = _selectedRegion;
      if (region == null || result.value.code != region.bmkgCode) {
        if (region != null) loadRegion(region);
        return;
      }
      _bmkgRegionForecast = result.value;
      _bmkgRegionErrorMessage = null;
    } else if (result is Error<BmkgMaritimForecast>) {
      _bmkgRegionErrorMessage =
          result.error.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> load(LatLng point, {bool forceRefresh = false}) =>
      loadCommand.execute((point, forceRefresh));

  Future<void> refresh() async {
    if (_point != null) {
      await load(_point!, forceRefresh: true);
    }
  }

  /// Memuat ramalan gelombang di titik tengah [region]. Ramalan titik
  /// posisi user tidak disentuh. Wilayah berkode BMKG JUGA memuat
  /// prakiraan resmi BMKG (paralel, command terpisah) — panel
  /// menampilkan BMKG sebagai default bila tersedia, Open-Meteo
  /// bila BMKG gagal/kosong. Wilayah tanpa kode BMKG: Open-Meteo
  /// saja (tidak ada endpoint BMKG-nya).
  Future<void> loadRegion(SeaRegion region,
      {bool forceRefresh = false}) async {
    _selectedRegion = region;
    _regionForecast = null;
    _regionErrorMessage = null;
    _bmkgRegionForecast = null;
    _bmkgRegionErrorMessage = null;
    _regionSourceOverride = null;
    notifyListeners();
    final code = region.bmkgCode;
    // Kedua sumber dimuat paralel — BMKG gagal tidak memblokir
    // Open-Meteo dan sebaliknya.
    await Future.wait([
      regionLoadCommand.execute((
        LatLng(region.latitude, region.longitude),
        forceRefresh,
      )),
      if (code != null && _bmkgRepository != null)
        bmkgRegionLoadCommand.execute((code, forceRefresh)),
    ]);
  }

  Future<void> refreshRegion() async {
    final region = _selectedRegion;
    if (region != null) {
      await loadRegion(region, forceRefresh: true);
    }
  }

  void clearRegion() {
    _selectedRegion = null;
    _regionForecast = null;
    _regionErrorMessage = null;
    _bmkgRegionForecast = null;
    _bmkgRegionErrorMessage = null;
    _regionSourceOverride = null;
    notifyListeners();
  }

  @override
  void dispose() {
    loadCommand.removeListener(_onLoadChanged);
    loadCommand.dispose();
    regionLoadCommand.removeListener(_onRegionLoadChanged);
    regionLoadCommand.dispose();
    bmkgRegionLoadCommand.removeListener(_onBmkgRegionLoadChanged);
    bmkgRegionLoadCommand.dispose();
    super.dispose();
  }
}
