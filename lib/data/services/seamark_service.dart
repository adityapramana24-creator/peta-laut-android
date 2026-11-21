import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/seamark.dart';
import '../../utils/result.dart';
import 'api_client.dart';

/// Rambu laut dari OpenStreetMap via Overpass API (gratis, tanpa kunci).
///
/// CATATAN RISET (ronde 2, butir 20): Overpass dari jaringan VM ini
/// TIDAK terverifikasi live (overpass-api.de 406 persisten, mirror
/// timeout/403) — itu BUKAN bukti Overpass mati; verifikasi live dari
/// jaringan/HP nyata tetap diperlukan. Karena itu service ini memakai
/// RANTAI FALLBACK 4 endpoint + UI gagal-jujur: bila SEMUA endpoint
/// gagal, hasilnya [loadFailedMessage] — JANGAN pernah menampilkan
/// error mentah, dan JANGAN pernah mengklaim Overpass mati.
///
/// Hemat request (user di kapal, koneksi terbatas):
/// - hanya dipanggil overlay pada zoom >= [minZoom];
/// - cache SharedPreferences JSON TTL 7 hari per bbox (dibulatkan
///   0,01 derajat) + cache memori per sesi;
/// - maks [maxConcurrent] request bersamaan (semaphore);
/// - maks [maxMarkers] rambu per bbox (yang terdekat dari tengah
///   bbox dipertahankan).
class SeamarkService {
  SeamarkService({ApiClient? client, SharedPreferences? prefs})
      : _client = client ?? ApiClient(),
        _prefs = prefs;

  final ApiClient _client;
  final SharedPreferences? _prefs;

  /// Rambu hanya dimuat pada zoom ini ke atas: di bawah zoom 12 satu
  /// layar mencakup puluhan km sehingga marker rambu menumpuk dan
  /// query bbox-nya terlalu besar.
  static const double minZoom = 12.0;

  /// Batas marker per bbox (layar tidak penuh + hemat memori).
  static const int maxMarkers = 200;

  /// Maksimum request Overpass yang berjalan bersamaan.
  static const int maxConcurrent = 2;

  /// Umur cache: rambu jarang berubah; 7 hari sesuai kebijakan
  /// cache OSM (TTL >= 7 hari).
  static const Duration cacheTtl = Duration(days: 7);

  static const Duration requestTimeout = Duration(seconds: 30);

  /// Rantai endpoint Overpass — utama dulu, lalu fallback berurutan.
  static const List<String> overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  /// Pesan gagal-jujur bila SEMUA endpoint gagal.
  static const String loadFailedMessage =
      'Data rambu tidak bisa dimuat — coba lagi nanti';

  /// Pesan bila bbox tidak punya data rambu (BUKAN error).
  static const String emptyMessage =
      'Tidak ada data rambu di area ini (OpenStreetMap)';

  static const _cachePrefix = 'seamark_bbox|';

  final _memoryCache = <String, _CachedSeamarks>{};
  int _inFlight = 0;
  final _waiters = <Completer<void>>[];

  /// Rambu di dalam bbox. Daftar KOSONG adalah hasil sukses (area
  /// tanpa data rambu) — bukan error. Error hanya bila SEMUA endpoint
  /// gagal.
  Future<Result<List<Seamark>>> fetchSeamarks({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final key = _cacheKey(south, west, north, east);
    final cached = _readMemoryCache(key) ?? await _readPrefsCache(key);
    if (cached != null) return Result.ok(cached);
    await _acquire();
    try {
      // Cek lagi setelah menunggu giliran — request lain mungkin
      // sudah mengisi cache untuk bbox yang sama.
      final cachedAfterWait =
          _readMemoryCache(key) ?? await _readPrefsCache(key);
      if (cachedAfterWait != null) return Result.ok(cachedAfterWait);
      final centerLat = (south + north) / 2;
      final centerLon = (west + east) / 2;
      final query = buildQuery(
        south: south,
        west: west,
        north: north,
        east: east,
      );
      for (final endpoint in overpassEndpoints) {
        final uri =
            Uri.parse(endpoint).replace(queryParameters: {'data': query});
        final result = await _client.get(uri, timeout: requestTimeout);
        if (result is! Ok<String>) {
          // Endpoint gagal — coba berikut.
          continue;
        }
        try {
          final seamarks = parseOverpassResponse(
            result.value,
            centerLat: centerLat,
            centerLon: centerLon,
          );
          await _writeCache(key, seamarks);
          return Result.ok(seamarks);
        } on FormatException {
          // Respons bukan JSON Overpass yang valid — coba endpoint
          // berikut.
          continue;
        }
      }
      return Result.error(Exception(loadFailedMessage));
    } finally {
      _release();
    }
  }

  /// Query Overpass QL: semua node/way/relation bertag `seamark:type`
  /// di bbox. `out center` memberi koordinat tengah untuk way/relation
  /// (tanpa itu way/relation tidak punya titik untuk marker).
  /// Urutan bbox Overpass: (selatan, barat, utara, timur).
  static String buildQuery({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    final bbox =
        '(${south.toStringAsFixed(6)},${west.toStringAsFixed(6)},'
        '${north.toStringAsFixed(6)},${east.toStringAsFixed(6)})';
    return '[out:json][timeout:25];'
        '(node["seamark:type"]$bbox;'
        'way["seamark:type"]$bbox;'
        'relation["seamark:type"]$bbox;);'
        'out center;';
  }

  /// Parse respons JSON Overpass menjadi daftar rambu.
  /// - Node memakai lat/lon; way/relation memakai `center`
  ///   (tanpa center, elemen dilewati — tidak ada titik marker).
  /// - Elemen tanpa tag `seamark:type` dilewati.
  /// - Bila [centerLat]/[centerLon] diberi, diurutkan terdekat dulu
  ///   dari tengah bbox agar cap [maxMarkers] mempertahankan yang
  ///   paling relevan.
  /// - Lempar [FormatException] bila body bukan JSON Overpass yang
  ///   valid (pemanggil memperlakukannya sebagai endpoint gagal,
  ///   BUKAN sebagai hasil kosong).
  static List<Seamark> parseOverpassResponse(
    String body, {
    double? centerLat,
    double? centerLon,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respons Overpass bukan objek JSON.');
    }
    final elements = decoded['elements'];
    if (elements is! List) {
      throw const FormatException('Respons Overpass tanpa elements.');
    }
    final seamarks = <Seamark>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;
      final type = element['type'];
      final id = element['id'];
      if (type is! String || id == null) continue;
      double? lat;
      double? lon;
      if (type == 'node') {
        final rawLat = element['lat'];
        final rawLon = element['lon'];
        if (rawLat is num) lat = rawLat.toDouble();
        if (rawLon is num) lon = rawLon.toDouble();
      } else {
        // way / relation: koordinat dari `center` (`out center`).
        final center = element['center'];
        if (center is Map<String, dynamic>) {
          final rawLat = center['lat'];
          final rawLon = center['lon'];
          if (rawLat is num) lat = rawLat.toDouble();
          if (rawLon is num) lon = rawLon.toDouble();
        }
      }
      if (lat == null || lon == null) continue;
      final tags = element['tags'];
      if (tags is! Map) continue;
      final seamark = Seamark.fromOsmTags(
        id: '$type/$id',
        latitude: lat,
        longitude: lon,
        tags: tags.map((k, v) => MapEntry(k.toString(), v.toString())),
      );
      if (seamark != null) seamarks.add(seamark);
    }
    if (centerLat != null && centerLon != null) {
      // Jarak kuadrat derajat — cukup untuk urutan (bbox kecil).
      double dist2(Seamark s) {
        final dLat = s.latitude - centerLat;
        final dLon = s.longitude - centerLon;
        return dLat * dLat + dLon * dLon;
      }

      seamarks.sort((a, b) => dist2(a).compareTo(dist2(b)));
    }
    return seamarks.take(maxMarkers).toList();
  }

  String _cacheKey(
    double south,
    double west,
    double north,
    double east,
  ) =>
      '$_cachePrefix${south.toStringAsFixed(2)}|'
      '${west.toStringAsFixed(2)}|'
      '${north.toStringAsFixed(2)}|'
      '${east.toStringAsFixed(2)}';

  List<Seamark>? _readMemoryCache(String key) {
    final cached = _memoryCache[key];
    if (cached == null || !cached.isFresh) return null;
    return cached.items;
  }

  Future<List<Seamark>?> _readPrefsCache(String key) async {
    final prefs = _prefs;
    if (prefs == null) return null;
    try {
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAtMs = decoded['fetchedAt'];
      final items = decoded['items'];
      if (fetchedAtMs is! int || items is! List) return null;
      final fetchedAt =
          DateTime.fromMillisecondsSinceEpoch(fetchedAtMs);
      if (DateTime.now().difference(fetchedAt) >= cacheTtl) return null;
      final seamarks = <Seamark>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final seamark = Seamark.fromJson(item);
        if (seamark != null) seamarks.add(seamark);
      }
      _memoryCache[key] =
          _CachedSeamarks(fetchedAt: fetchedAt, items: seamarks);
      return seamarks;
    } catch (_) {
      // Cache rusak — abaikan, fetch ulang dari jaringan.
      return null;
    }
  }

  Future<void> _writeCache(String key, List<Seamark> seamarks) async {
    final fetchedAt = DateTime.now();
    _memoryCache[key] =
        _CachedSeamarks(fetchedAt: fetchedAt, items: seamarks);
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        key,
        jsonEncode({
          'fetchedAt': fetchedAt.millisecondsSinceEpoch,
          'items': seamarks.map((s) => s.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Cache gagal ditulis — data tetap dipakai.
    }
  }

  /// Semaphore sederhana: maks [maxConcurrent] request bersamaan.
  Future<void> _acquire() async {
    if (_inFlight < maxConcurrent) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  void _release() {
    _inFlight--;
    if (_waiters.isNotEmpty) {
      _inFlight++;
      _waiters.removeAt(0).complete();
    }
  }
}

class _CachedSeamarks {
  const _CachedSeamarks({required this.fetchedAt, required this.items});

  final DateTime fetchedAt;
  final List<Seamark> items;

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < SeamarkService.cacheTtl;
}
