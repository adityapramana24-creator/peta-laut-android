import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan kunci AIS di secure storage perangkat
/// (Keystore Android — terenkripsi, tidak di SharedPreferences).
/// Nilai kunci TIDAK PERNAH di-log, ditampilkan, atau ditulis ke file
/// lain. Service ini hanya menyimpan/mengambil/menghapus.
class SecureKeyService {
  SecureKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String aisKeyName = 'aisstream_api_key';

  final FlutterSecureStorage _storage;

  Future<void> saveAisKey(String key) async {
    await _storage.write(key: aisKeyName, value: key.trim());
  }

  Future<String?> readAisKey() async {
    return _storage.read(key: aisKeyName);
  }

  Future<bool> hasAisKey() async {
    final value = await _storage.read(key: aisKeyName);
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> deleteAisKey() async {
    await _storage.delete(key: aisKeyName);
  }
}
