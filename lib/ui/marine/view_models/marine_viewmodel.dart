import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/sea_regions.dart';
import '../../../data/repositories/marine_repository.dart';
import '../../../domain/models/marine.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// ViewModel panel Gelombang (R-15): Open-Meteo Marine 3 hari.
/// Titik darat -> hasData false -> UI menampilkan "tidak ada data",
/// BUKAN 0.
///
/// Ronde 2: DITAMBAH ramalan per wilayah laut ([SeaRegion]) — state +
/// command TERPISAH dari ramalan titik posisi user. Perilaku titik
/// TIDAK berubah: [load]/[refresh]/[forecast]/[point] sama seperti
/// sebelumnya; wilayah dimuat lewat [loadRegion] dengan lat/lon titik
/// tengah wilayah, memakai repository + cache yang sama.
class MarineViewModel extends ChangeNotifier {
  MarineViewModel({required MarineRepository repository})
      : _repository = repository {
    loadCommand = Command1(_load);
    loadCommand.addListener(_onLoadChanged);
    regionLoadCommand = Command1(_loadRegion);
    regionLoadCommand.addListener(_onRegionLoadChanged);
  }

  final MarineRepository _repository;
  late final Command1<MarineForecast, (LatLng, bool)> loadCommand;
  late final Command1<MarineForecast, (LatLng, bool)> regionLoadCommand;

  MarineForecast? _forecast;
  LatLng? _point;
  String? _errorMessage;

  SeaRegion? _selectedRegion;
  MarineForecast? _regionForecast;
  String? _regionErrorMessage;

  MarineForecast? get forecast => _forecast;
  LatLng? get point => _point;
  String? get errorMessage => _errorMessage;
  bool get loading => loadCommand.running;

  SeaRegion? get selectedRegion => _selectedRegion;
  MarineForecast? get regionForecast => _regionForecast;
  String? get regionErrorMessage => _regionErrorMessage;
  bool get regionLoading => regionLoadCommand.running;

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
      _regionForecast = result.value;
      _regionErrorMessage = null;
    } else if (result is Error<MarineForecast>) {
      _regionErrorMessage =
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
  /// posisi user tidak disentuh.
  Future<void> loadRegion(SeaRegion region,
      {bool forceRefresh = false}) async {
    _selectedRegion = region;
    _regionForecast = null;
    _regionErrorMessage = null;
    notifyListeners();
    await regionLoadCommand.execute((
      LatLng(region.latitude, region.longitude),
      forceRefresh,
    ));
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
    notifyListeners();
  }

  @override
  void dispose() {
    loadCommand.removeListener(_onLoadChanged);
    loadCommand.dispose();
    regionLoadCommand.removeListener(_onRegionLoadChanged);
    regionLoadCommand.dispose();
    super.dispose();
  }
}
