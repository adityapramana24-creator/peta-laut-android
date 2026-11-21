import 'package:flutter/foundation.dart';

import '../../../data/repositories/ais_repository.dart';
import '../../../domain/models/vessel.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// ViewModel panel AIS + seksi AIS di Pengaturan (R-18, R-19).
/// Kunci TIDAK PERNAH disimpan di VM ini selain saat diteruskan ke
/// repository (disimpan di secure storage, tidak di-log/ditampilkan).
class AisViewModel extends ChangeNotifier {
  AisViewModel({required AisRepository repository})
      : _repository = repository {
    saveKeyCommand = Command1(_saveKey);
    testCommand = Command1(_testKey);
    saveKeyCommand.addListener(_onSaveChanged);
    testCommand.addListener(_onTestChanged);
    _vessels = _repository.vessels;
    _state = _repository.state;
    _repository.vesselsStream.listen((vessels) {
      _vessels = vessels;
      notifyListeners();
    });
    _repository.connectionState.listen((state) {
      _state = state;
      notifyListeners();
    });
  }

  final AisRepository _repository;

  /// saveKeyCommand membawa (kunci, bbox) — bbox dari MapViewModel.
  late final Command1<bool, (String, (double, double, double, double))>
      saveKeyCommand;
  late final Command1<bool, String> testCommand;

  bool _hasKey = false;
  bool _keyChecked = false;
  Map<int, Vessel> _vessels = {};
  AisConnectionState _state = AisConnectionState.notConfigured;
  String? _statusMessage;
  bool _statusIsError = false;

  bool get hasKey => _hasKey;
  bool get keyChecked => _keyChecked;
  Map<int, Vessel> get vessels => _vessels;
  AisConnectionState get state => _state;
  String? get statusMessage => _statusMessage;
  bool get statusIsError => _statusIsError;

  /// Daftar kapal terurut nama (yang berposisi dulu).
  List<Vessel> get vesselList {
    final list = _vessels.values.toList();
    list.sort((a, b) {
      if (a.hasPosition != b.hasPosition) {
        return a.hasPosition ? -1 : 1;
      }
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  Future<void> init() async {
    _hasKey = await _repository.hasKey();
    _keyChecked = true;
    notifyListeners();
  }

  Future<Result<bool>> _saveKey(
    (String, (double, double, double, double)) args,
  ) async {
    final (key, bounds) = args;
    if (key.trim().isEmpty) {
      return Result.error(Exception('Kunci masih kosong.'));
    }
    try {
      await _repository.saveKey(key);
      _hasKey = true;
      await _repository.connectIfConfigured(bounds: bounds);
      return const Result.ok(true);
    } catch (e) {
      return Result.error(Exception('Gagal menyimpan kunci: $e'));
    }
  }

  Future<Result<bool>> _testKey(String key) {
    if (key.trim().isEmpty) {
      return Future.value(
        Result.error(Exception('Kunci masih kosong.')),
      );
    }
    return _repository.testConnection(key.trim());
  }

  void _onSaveChanged() {
    final result = saveKeyCommand.result;
    if (result is Ok<bool>) {
      _statusMessage = 'Kunci tersimpan. Menghubungkan ke AISStream…';
      _statusIsError = false;
    } else if (result is Error<bool>) {
      _statusMessage =
          result.error.toString().replaceFirst('Exception: ', '');
      _statusIsError = true;
    }
    notifyListeners();
  }

  void _onTestChanged() {
    final result = testCommand.result;
    if (result is Ok<bool>) {
      _statusMessage = 'Kunci valid — sambungan AISStream berhasil.';
      _statusIsError = false;
    } else if (result is Error<bool>) {
      _statusMessage =
          result.error.toString().replaceFirst('Exception: ', '');
      _statusIsError = true;
    }
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
    notifyListeners();
  }

  Future<void> deleteKey() async {
    await _repository.deleteKey();
    _hasKey = false;
    _statusMessage = 'Kunci AIS dihapus.';
    _statusIsError = false;
    notifyListeners();
  }

  @override
  void dispose() {
    saveKeyCommand.removeListener(_onSaveChanged);
    testCommand.removeListener(_onTestChanged);
    saveKeyCommand.dispose();
    testCommand.dispose();
    super.dispose();
  }
}
