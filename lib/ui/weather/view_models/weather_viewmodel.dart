import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/map_data_repository.dart';
import '../../../data/repositories/weather_repository.dart';
import '../../../domain/models/port.dart';
import '../../../domain/models/weather.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// ViewModel panel Cuaca (R-14): BMKG 3 hari per pelabuhan.
/// Default: pelabuhan terdekat dari titik acuan.
class WeatherViewModel extends ChangeNotifier {
  WeatherViewModel({
    required WeatherRepository repository,
    required MapDataRepository mapDataRepository,
  })  : _repository = repository,
        _mapDataRepository = mapDataRepository {
    loadCommand = Command1(_load);
    loadCommand.addListener(_onLoadChanged);
  }

  final WeatherRepository _repository;
  final MapDataRepository _mapDataRepository;
  late final Command1<BmkgForecast, (String, bool)> loadCommand;

  Port? _port;
  BmkgForecast? _forecast;
  String? _errorMessage;

  Port? get port => _port;
  BmkgForecast? get forecast => _forecast;
  String? get errorMessage => _errorMessage;
  bool get loading => loadCommand.running;
  List<Port> get ports => Port.all;

  Future<Result<BmkgForecast>> _load((String, bool) args) async {
    final (adm4, forceRefresh) = args;
    return _repository.getBmkg(adm4: adm4, forceRefresh: forceRefresh);
  }

  void _onLoadChanged() {
    final result = loadCommand.result;
    if (result is Ok<BmkgForecast>) {
      _forecast = result.value;
      _errorMessage = null;
    } else if (result is Error<BmkgForecast>) {
      _errorMessage =
          result.error.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> loadForPoint(LatLng point) async {
    _port = _mapDataRepository.nearestPort(point.latitude, point.longitude);
    notifyListeners();
    await loadCommand.execute((_port!.adm4, false));
  }

  Future<void> selectPort(Port port) async {
    _port = port;
    _forecast = null;
    notifyListeners();
    await loadCommand.execute((port.adm4, false));
  }

  Future<void> refresh() async {
    if (_port != null) {
      await loadCommand.execute((_port!.adm4, true));
    }
  }

  @override
  void dispose() {
    loadCommand.removeListener(_onLoadChanged);
    loadCommand.dispose();
    super.dispose();
  }
}
