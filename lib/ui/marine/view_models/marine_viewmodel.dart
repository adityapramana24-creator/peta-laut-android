import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/marine_repository.dart';
import '../../../domain/models/marine.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// ViewModel panel Gelombang (R-15): Open-Meteo Marine 3 hari.
/// Titik darat -> hasData false -> UI menampilkan "tidak ada data",
/// BUKAN 0.
class MarineViewModel extends ChangeNotifier {
  MarineViewModel({required MarineRepository repository})
      : _repository = repository {
    loadCommand = Command1(_load);
    loadCommand.addListener(_onLoadChanged);
  }

  final MarineRepository _repository;
  late final Command1<MarineForecast, (LatLng, bool)> loadCommand;

  MarineForecast? _forecast;
  LatLng? _point;
  String? _errorMessage;

  MarineForecast? get forecast => _forecast;
  LatLng? get point => _point;
  String? get errorMessage => _errorMessage;
  bool get loading => loadCommand.running;

  Future<Result<MarineForecast>> _load((LatLng, bool) args) async {
    final (point, forceRefresh) = args;
    _point = point;
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

  Future<void> load(LatLng point, {bool forceRefresh = false}) =>
      loadCommand.execute((point, forceRefresh));

  Future<void> refresh() async {
    if (_point != null) {
      await load(_point!, forceRefresh: true);
    }
  }

  @override
  void dispose() {
    loadCommand.removeListener(_onLoadChanged);
    loadCommand.dispose();
    super.dispose();
  }
}
