import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/repositories/tides_repository.dart';
import '../../../domain/models/tide.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// ViewModel panel Pasang Surut (R-13): ekstremum hari ini + besok WIB
/// + kurva 48 jam. Command1 membawa (titik, forceRefresh).
class TidesViewModel extends ChangeNotifier {
  TidesViewModel({required TidesRepository repository})
      : _repository = repository {
    loadCommand = Command1(_load);
    loadCommand.addListener(_onLoadChanged);
  }

  final TidesRepository _repository;
  late final Command1<TideForecast, (LatLng, bool)> loadCommand;

  TideForecast? _forecast;
  LatLng? _point;
  String? _errorMessage;

  TideForecast? get forecast => _forecast;
  LatLng? get point => _point;
  String? get errorMessage => _errorMessage;
  bool get loading => loadCommand.running;

  Future<Result<TideForecast>> _load((LatLng, bool) args) async {
    final (point, forceRefresh) = args;
    _point = point;
    return _repository.getTides(
      latitude: point.latitude,
      longitude: point.longitude,
      forceRefresh: forceRefresh,
    );
  }

  void _onLoadChanged() {
    final result = loadCommand.result;
    if (result is Ok<TideForecast>) {
      _forecast = result.value;
      _errorMessage = null;
    } else if (result is Error<TideForecast>) {
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
