import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/anchor_mob.dart';

/// Alarm jangkar + tanda MOB (R-28), disimpan di SharedPreferences.
/// Data kecil dan jarang berubah — tidak perlu tabel Drift baru.
class SafetyRepository {
  SafetyRepository({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static const _keyAnchor = 'anchor_settings';
  static const _keyMobMarks = 'mob_marks';

  // -- Alarm jangkar --

  AnchorSettings? get anchor {
    final raw = _prefs.getString(_keyAnchor);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AnchorSettings.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAnchor(AnchorSettings settings) async {
    await _prefs.setString(_keyAnchor, jsonEncode(settings.toJson()));
  }

  Future<void> clearAnchor() async {
    await _prefs.remove(_keyAnchor);
  }

  // -- Tanda MOB --

  List<MobMark> get mobMarks {
    final raw = _prefs.getString(_keyMobMarks);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(MobMark.fromJson)
          .where((m) => m.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> addMobMark(MobMark mark) async {
    final list = mobMarks..add(mark);
    await _prefs.setString(
      _keyMobMarks,
      jsonEncode(list.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> deleteMobMark(String id) async {
    final list = mobMarks.where((m) => m.id != id).toList();
    await _prefs.setString(
      _keyMobMarks,
      jsonEncode(list.map((m) => m.toJson()).toList()),
    );
  }
}
